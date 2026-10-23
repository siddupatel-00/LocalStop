use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use tauri::Manager;

#[derive(Default, Serialize, Deserialize)]
struct Store {
    #[serde(default)]
    names: HashMap<String, String>,
}

fn path(app: &tauri::AppHandle) -> Option<PathBuf> {
    app.path()
        .app_config_dir()
        .ok()
        .map(|dir| dir.join("servers.json"))
}

fn read(app: &tauri::AppHandle) -> Result<Store, String> {
    let Some(path) = path(app) else {
        return Ok(Store::default());
    };

    match fs::read(&path) {
        Ok(data) => serde_json::from_slice(&data).map_err(|error| error.to_string()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Store::default()),
        Err(error) => Err(error.to_string()),
    }
}

pub fn load(app: &tauri::AppHandle) -> HashMap<String, String> {
    read(app).map(|store| store.names).unwrap_or_default()
}

pub fn set(app: &tauri::AppHandle, port: u16, name: &str) -> Result<(), String> {
    let mut store = read(app)?;
    let key = port.to_string();
    let trimmed = name.trim();

    if trimmed.is_empty() {
        store.names.remove(&key);
    } else {
        store.names.insert(key, trimmed.to_string());
    }

    let path = path(app).ok_or("Could not resolve config directory")?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }

    let data = serde_json::to_vec_pretty(&store).map_err(|error| error.to_string())?;
    let temporary = path.with_extension("json.tmp");
    fs::write(&temporary, data).map_err(|error| error.to_string())?;

    if fs::rename(&temporary, &path).is_err() {
        let _ = fs::remove_file(&path);
        fs::rename(&temporary, &path).map_err(|error| error.to_string())?;
    }

    Ok(())
}
