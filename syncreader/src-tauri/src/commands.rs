use crate::alignment::{self, AlignmentResult};
use crate::project::{self, Project};
use crate::tts::{self, TTSProvider, TTSResult};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WordTimestamp {
    pub word: String,
    pub start: f64,
    pub end: f64,
    pub sentence_index: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SentenceBoundary {
    pub index: usize,
    pub start_word_index: usize,
    pub end_word_index: usize,
    pub start: f64,
    pub end: f64,
    pub speaker: Option<String>,
}

/// Open a native file-picker dialog.
///
/// `filter` is a comma-separated list of extensions, e.g. "mp3,wav,ogg".
/// Returns the selected absolute path, or `None` when the user cancels.
///
/// NOTE: The Tauri 2.x dialog plugin exposes its blocking picker API from the
/// frontend via `@tauri-apps/plugin-dialog`.  This command is kept as a
/// registered shim so the invoke_handler sees all eight commands; the frontend
/// should call `open()` from the JS plugin directly for the actual dialog.
#[tauri::command]
pub async fn select_file(filter: String) -> Result<Option<String>, String> {
    let _ = filter;
    Ok(None)
}

/// Read a UTF-8 text file from the given absolute path.
///
/// Rejects paths that are not absolute or that contain any `..` component to
/// prevent directory traversal outside the intended scope.
#[tauri::command]
pub async fn read_text_file(path: String) -> Result<String, String> {
    let p = PathBuf::from(&path);

    if !p.is_absolute() {
        return Err(format!("Path must be absolute, got: '{}'", path));
    }

    // Reject any path component equal to `..`.
    if p.components().any(|c| c == std::path::Component::ParentDir) {
        return Err(format!("Path must not contain '..' components: '{}'", path));
    }

    std::fs::read_to_string(&p).map_err(|e| format!("Failed to read file '{}': {}", path, e))
}

/// Convert a filesystem path to an asset:// URL the Tauri webview can load.
#[tauri::command]
pub async fn get_asset_url(path: String) -> Result<String, String> {
    let path = PathBuf::from(&path);
    if !path.exists() {
        return Err(format!("File not found: {}", path.display()));
    }
    // Tauri 2.x serves local assets via asset://localhost/<absolute-path>
    // The path must use forward slashes even on Windows.
    let normalized = path.to_string_lossy().replace('\\', "/");
    Ok(format!("asset://localhost/{}", normalized))
}

/// Run forced alignment on `audio_path` against the provided `text`.
#[tauri::command]
pub async fn align_audio(audio_path: String, text: String) -> Result<AlignmentResult, String> {
    alignment::align(&audio_path, &text).await
}

/// Generate TTS audio for `text` using the specified provider.
///
/// `provider` must be one of: "elevenlabs", "gemini", "inworld".
/// `output_dir` is the directory where the audio file will be saved.
/// Returns the path of the written audio file, plus optional word timestamps.
#[tauri::command]
pub async fn generate_tts(
    text: String,
    provider: String,
    voice: String,
    api_key: String,
    output_dir: String,
) -> Result<TTSResult, String> {
    let tts_provider = match provider.as_str() {
        "elevenlabs" => TTSProvider::ElevenLabs,
        "gemini" => TTSProvider::Gemini,
        "inworld" => TTSProvider::Inworld,
        _ => return Err(format!("Unknown TTS provider: '{}'. Valid values: elevenlabs, gemini, inworld", provider)),
    };
    tts::generate(&text, tts_provider, &voice, &api_key, &output_dir).await
}

/// Persist a project to disk and return its ID.
#[tauri::command]
pub async fn save_project(project: Project) -> Result<String, String> {
    project::save(&project).await
}

/// Load a project by its ID.
#[tauri::command]
pub async fn load_project(id: String) -> Result<Project, String> {
    project::load(&id).await
}

/// Return metadata for all saved projects, sorted newest-first.
#[tauri::command]
pub async fn list_projects() -> Result<Vec<project::ProjectMeta>, String> {
    project::list().await
}
