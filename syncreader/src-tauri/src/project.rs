use crate::commands::{SentenceBoundary, WordTimestamp};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// A complete SyncReader project as stored on disk.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub id: String,
    pub title: String,
    pub text: String,
    pub timestamps: Vec<WordTimestamp>,
    pub sentences: Vec<SentenceBoundary>,
    pub audio_path: String,
    pub language: String,
    /// ISO 8601 datetime string, e.g. "2026-03-19T14:30:00Z"
    pub created_at: String,
    /// ISO 8601 datetime string
    pub updated_at: String,
}

/// Lightweight summary returned by `list_projects`.
#[derive(Debug, Serialize, Deserialize)]
pub struct ProjectMeta {
    pub id: String,
    pub title: String,
    pub language: String,
    pub created_at: String,
    pub updated_at: String,
}

/// Return (and create if necessary) the per-user projects directory.
///
/// On macOS: `~/Library/Application Support/syncreader/projects`
/// On Linux: `~/.local/share/syncreader/projects`
/// On Windows: `%APPDATA%\syncreader\projects`
fn projects_dir() -> Result<PathBuf, String> {
    let dir = dirs::data_dir()
        .ok_or_else(|| "Could not locate the system data directory".to_string())?
        .join("syncreader")
        .join("projects");

    std::fs::create_dir_all(&dir)
        .map_err(|e| format!("Failed to create projects directory '{}': {}", dir.display(), e))?;

    Ok(dir)
}

fn project_file(dir: &PathBuf, id: &str) -> PathBuf {
    dir.join(format!("{}.json", id))
}

/// Write a project to `<projects_dir>/<id>.json` and return the project ID.
pub async fn save(project: &Project) -> Result<String, String> {
    // Basic validation — IDs must not contain path separators.
    if project.id.contains('/') || project.id.contains('\\') {
        return Err(format!("Invalid project ID: '{}'", project.id));
    }

    let dir = projects_dir()?;
    let file_path = project_file(&dir, &project.id);

    let json = serde_json::to_string_pretty(project)
        .map_err(|e| format!("Failed to serialize project '{}': {}", project.id, e))?;

    std::fs::write(&file_path, json)
        .map_err(|e| format!("Failed to write project file '{}': {}", file_path.display(), e))?;

    Ok(project.id.clone())
}

/// Load and deserialize a project by its ID.
pub async fn load(id: &str) -> Result<Project, String> {
    if id.contains('/') || id.contains('\\') {
        return Err(format!("Invalid project ID: '{}'", id));
    }

    let dir = projects_dir()?;
    let file_path = project_file(&dir, id);

    let json = std::fs::read_to_string(&file_path)
        .map_err(|e| format!("Failed to read project '{}': {}", id, e))?;

    serde_json::from_str(&json)
        .map_err(|e| format!("Failed to parse project '{}': {}", id, e))
}

/// Return metadata for every saved project, sorted by `updated_at` descending.
///
/// Projects whose files cannot be read or parsed are silently skipped so that
/// a single corrupt file does not prevent the UI from listing the rest.
pub async fn list() -> Result<Vec<ProjectMeta>, String> {
    let dir = projects_dir()?;

    let entries = std::fs::read_dir(&dir)
        .map_err(|e| format!("Failed to list projects directory: {}", e))?;

    let mut projects: Vec<ProjectMeta> = entries
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let path = entry.path();
            if path.extension()?.to_str()? != "json" {
                return None;
            }
            let json = std::fs::read_to_string(&path).ok()?;
            let project: Project = serde_json::from_str(&json).ok()?;
            Some(ProjectMeta {
                id: project.id,
                title: project.title,
                language: project.language,
                created_at: project.created_at,
                updated_at: project.updated_at,
            })
        })
        .collect();

    // Newest first.
    projects.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));

    Ok(projects)
}
