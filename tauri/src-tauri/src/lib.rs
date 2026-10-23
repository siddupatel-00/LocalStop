use std::collections::HashMap;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{Manager, WindowEvent};

mod config;
mod scanner;

#[tauri::command]
async fn list_servers() -> Result<Vec<scanner::Server>, String> {
    tauri::async_runtime::spawn_blocking(scanner::scan)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
async fn stop_server(pid: u32) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || scanner::stop(pid))
        .await
        .map_err(|error| error.to_string())?
}

#[tauri::command]
fn get_names(app: tauri::AppHandle) -> HashMap<String, String> {
    config::load(&app)
}

#[tauri::command]
fn set_name(app: tauri::AppHandle, port: u16, name: String) -> Result<(), String> {
    config::set(&app, port, &name)
}

#[tauri::command]
fn open_url(url: String) -> Result<(), String> {
    scanner::open_url(&url)
}

#[tauri::command]
fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
}

#[tauri::command]
fn hide_window(app: tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide();
    }
}

fn place_window(window: &tauri::WebviewWindow, anchor: Option<tauri::Rect>) {
    let Some(rect) = anchor else {
        let _ = window.center();
        return;
    };

    let scale = window.scale_factor().unwrap_or(1.0);
    let monitor = window
        .current_monitor()
        .ok()
        .flatten()
        .or_else(|| window.primary_monitor().ok().flatten());

    let Some(monitor) = monitor else {
        let _ = window.center();
        return;
    };

    let monitor_position = monitor.position().to_logical::<f64>(scale);
    let monitor_size = monitor.size().to_logical::<f64>(scale);
    let window_size = window
        .outer_size()
        .map(|size| size.to_logical::<f64>(scale))
        .unwrap_or(tauri::LogicalSize::new(380.0, 560.0));

    let tray_position = rect.position.to_logical::<f64>(scale);
    let tray_size = rect.size.to_logical::<f64>(scale);

    if !tray_size.width.is_finite() || tray_size.width <= 0.0 {
        let _ = window.center();
        return;
    }

    let mut x = tray_position.x + tray_size.width / 2.0 - window_size.width / 2.0;
    let mut y = if tray_position.y < monitor_position.y + monitor_size.height / 2.0 {
        tray_position.y + tray_size.height + 6.0
    } else {
        tray_position.y - window_size.height - 6.0
    };

    x = x.max(monitor_position.x + 8.0);
    x = x.min(monitor_position.x + monitor_size.width - window_size.width - 8.0);
    y = y.max(monitor_position.y + 8.0);
    y = y.min(monitor_position.y + monitor_size.height - window_size.height - 8.0);

    let _ = window.set_position(tauri::LogicalPosition::new(x, y));
}

fn show_window(app: &tauri::AppHandle, anchor: Option<tauri::Rect>) {
    let Some(window) = app.get_webview_window("main") else {
        return;
    };
    place_window(&window, anchor);
    let _ = window.show();
    let _ = window.set_focus();
}

fn toggle_window(app: &tauri::AppHandle, anchor: Option<tauri::Rect>) {
    let Some(window) = app.get_webview_window("main") else {
        return;
    };

    if window.is_visible().unwrap_or(false) {
        let _ = window.hide();
    } else {
        show_window(app, anchor);
    }
}

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            list_servers,
            stop_server,
            get_names,
            set_name,
            open_url,
            quit_app,
            hide_window
        ])
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.handle()
                .set_activation_policy(tauri::ActivationPolicy::Accessory)?;

            if let Some(window) = app.get_webview_window("main") {
                let window_for_events = window.clone();
                window.on_window_event(move |event| {
                    if let WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        let _ = window_for_events.hide();
                    }
                });
            }

            let show = MenuItem::with_id(app, "show", "Show / Hide LocalStop", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;

            let mut tray = TrayIconBuilder::with_id("main")
                .tooltip("LocalStop")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => toggle_window(app, None),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        rect,
                        ..
                    } = event
                    {
                        toggle_window(tray.app_handle(), Some(rect));
                    }
                });

            #[cfg(target_os = "macos")]
            {
                tray = tray.icon_as_template(true);
            }

            let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray.png"))?;
            tray.icon(icon).build(app)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running LocalStop");
}
