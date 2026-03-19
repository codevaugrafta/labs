use crate::commands::{SentenceBoundary, WordTimestamp};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// The JSON structure produced by `scripts/align.py`.
///
/// Python uses camelCase keys for the nested objects to match the frontend
/// TypeScript types directly.
#[derive(Debug, Serialize, Deserialize)]
pub struct AlignmentResult {
    pub timestamps: Vec<WordTimestamp>,
    pub sentences: Vec<SentenceBoundary>,
}

/// Run forced alignment via the Python sidecar (`scripts/align.py`).
///
/// The script uses stable-ts to align `text` with `audio_path` and writes a
/// JSON file whose schema matches `AlignmentResult`.
pub async fn align(audio_path: &str, text: &str) -> Result<AlignmentResult, String> {
    let tmp_dir = std::env::temp_dir();
    let text_path = tmp_dir.join("syncreader_align_text.txt");
    let output_path = tmp_dir.join("syncreader_align_output.json");

    std::fs::write(&text_path, text)
        .map_err(|e| format!("Failed to write temp text file: {}", e))?;

    let script_path = find_alignment_script()?;

    let output = std::process::Command::new("python3")
        .arg(&script_path)
        .arg("--audio")
        .arg(audio_path)
        .arg("--text")
        .arg(text_path.to_string_lossy().as_ref())
        .arg("--output")
        .arg(output_path.to_string_lossy().as_ref())
        .output()
        .map_err(|e| format!("Failed to spawn alignment script: {}", e))?;

    // Always clean up temp inputs — ignore removal errors.
    let _ = std::fs::remove_file(&text_path);

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // Clean up output file if it was partially written.
        let _ = std::fs::remove_file(&output_path);
        return Err(format!(
            "Alignment script exited with status {}: {}",
            output.status, stderr
        ));
    }

    let result_json = std::fs::read_to_string(&output_path)
        .map_err(|e| format!("Failed to read alignment output: {}", e))?;

    let _ = std::fs::remove_file(&output_path);

    let result: AlignmentResult = serde_json::from_str(&result_json)
        .map_err(|e| format!("Failed to parse alignment JSON: {}", e))?;

    Ok(result)
}

/// Locate `scripts/align.py` relative to the running executable (production)
/// or relative to the Cargo manifest directory (development).
fn find_alignment_script() -> Result<String, String> {
    // Production: the script is bundled next to the executable in a `scripts/` dir.
    if let Ok(exe) = std::env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            let candidate = exe_dir.join("scripts").join("align.py");
            if candidate.exists() {
                return Ok(candidate.to_string_lossy().to_string());
            }
        }
    }

    // Development: resolve from the workspace root (one level up from src-tauri).
    let dev_candidate = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .map(|root| root.join("scripts").join("align.py"))
        .filter(|p| p.exists());

    if let Some(path) = dev_candidate {
        return Ok(path.to_string_lossy().to_string());
    }

    Err(
        "Alignment script not found. \
         Expected at <app>/scripts/align.py (production) \
         or <project-root>/scripts/align.py (development)."
            .to_string(),
    )
}
