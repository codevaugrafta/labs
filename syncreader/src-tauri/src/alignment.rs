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
    let script_path = find_alignment_script()?;

    // Pass text via stdin and get JSON result via stdout — no temp files needed.
    let mut child = std::process::Command::new("python3")
        .arg(&script_path)
        .arg("--audio")
        .arg(audio_path)
        .arg("--stdin")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to spawn alignment script: {}", e))?;

    // Write text to stdin
    if let Some(mut stdin) = child.stdin.take() {
        use std::io::Write;
        stdin.write_all(text.as_bytes())
            .map_err(|e| format!("Failed to write text to alignment script: {}", e))?;
        // stdin is dropped here, closing the pipe
    }

    let output = child.wait_with_output()
        .map_err(|e| format!("Failed to wait for alignment script: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "Alignment script exited with status {}: {}",
            output.status, stderr
        ));
    }

    let result_json = String::from_utf8_lossy(&output.stdout);

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
