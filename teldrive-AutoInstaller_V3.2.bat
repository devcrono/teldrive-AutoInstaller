@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
color 0B
title Teldrive Installer Pro v3.2

if /i "%~1"=="__run_logged" goto cli_run_logged

:: =========================================================
:: CONFIG BASE
:: =========================================================
set "APP_NAME=Teldrive Installer Pro"
set "APP_VERSION=3.2"
set "LANG=pt"
set "DATE_MODE=LOCAL"

set "BASE_DIR=%~dp0"
set "TELDRIVE_DIR=%BASE_DIR%teldrive"
set "LOGFILE=%BASE_DIR%instalacao_teldrive.log"
set "CONFIG_FILE=%TELDRIVE_DIR%\config.toml"
set "SETTINGS_FILE=%TELDRIVE_DIR%\installer_settings.cfg"
set "MODE_FILE=%TELDRIVE_DIR%\installer_mode.cfg"
set "LAUNCHER_FILE=%BASE_DIR%teldrive_update_start.cmd"
set "TEMP_CONFIG_BACKUP=%BASE_DIR%config_pre_reinstall_backup.toml"

set "PORTA=8080"
set "SERVICE_MODE=0"
set "ANSWER="
set "INSTALL_MODE=UPDATE"
set "TELDRIVE_RUNNING=0"
set "RUN_PID="
set "RUN_PROC_NAME="
set "PORT_IN_USE=0"
set "PORT_PID="
set "PORT_PROC_NAME="
set "FOUND_CONFIG="

set "URL_REPO=https://github.com/tgdrive/teldrive.git"
set "URL_GIT=https://github.com/git-for-windows/git/releases/download/v2.46.0.windows.1/Git-2.46.0-64-bit.exe"
set "URL_GO=https://go.dev/dl/go1.23.1.windows-amd64.msi"
set "URL_NGROK=https://bin.equinox.io/c/bNyj1mQVY4/ngrok-v3-stable-windows-amd64.zip"
set "URL_CLOUDFLARED=https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe"

set "GIT_EXE=%ProgramFiles%\Git\cmd\git.exe"
set "GO_EXE=%ProgramFiles%\Go\bin\go.exe"

call :banner
call :select_language
call :detect_date_mode
call :load_settings
call :banner
call :log "Starting %APP_NAME% v%APP_VERSION%" "INFO"

call :etapa "1/7" "step_permissions"
call :check_admin
if errorlevel 1 exit /b 1

call :etapa "2/7" "step_internet"
call :check_internet
if errorlevel 1 exit /b 1

call :etapa "3/7" "step_running_check"
call :check_running_teldrive
if "!TELDRIVE_RUNNING!"=="1" (
    call :handle_running_instance
    if errorlevel 1 exit /b 1
) else (
    call :log_last_msg "running_not_found" "OK"
)

call :etapa "4/7" "step_dependencies"
call :ensure_git
if errorlevel 1 goto fatal
call :ensure_go
if errorlevel 1 goto fatal

call :etapa "5/7" "step_repo"
call :detect_existing_installation
if errorlevel 1 exit /b 1
call :prepare_repo
if errorlevel 1 goto fatal

call :etapa "6/7" "step_project_deps"
call :update_project_deps

call :etapa "7/7" "step_port"
call :check_port_only
if "!PORT_IN_USE!"=="1" (
    call :log_last_msg "port_in_use" "WARN"
    call :show_port_details
) else (
    call :log_last_msg "port_free" "OK"
)

goto check_config

:: =========================================================
:: CONFIG
:: =========================================================
:check_config
if exist "%MODE_FILE%" call :load_service_mode
if exist "%SETTINGS_FILE%" call :load_settings

call :find_existing_config
if exist "%CONFIG_FILE%" (
    call :log_msg "config_found" "OK"
    goto first_time_extras
)

if defined FOUND_CONFIG (
    echo.
    call :print_msg "external_config_found"
    echo     !FOUND_CONFIG!
    call :ask_yes_no "reuse_found_config"
    if /i "!ANSWER!"=="Y" (
        copy /y "!FOUND_CONFIG!" "%CONFIG_FILE%" >nul 2>&1
        if exist "%CONFIG_FILE%" (
            call :log "Reused config from !FOUND_CONFIG!" "OK"
            goto first_time_extras
        )
    )
)

call :etapa "CONFIG" "step_config"
call :ask_required "ask_db_url" db_url
call :ask_required "ask_app_id" app_id
call :ask_required "ask_app_hash" app_hash
call :ask_required "ask_jwt_secret" jwt_secret
echo.
call :prompt_text "ask_redis_optional" redis_url
set "bot_token="
call :prompt_text "ask_bot_yesno" tem_bot
if /i "!tem_bot!"=="s" call :ask_required "ask_bot_token" bot_token
if /i "!tem_bot!"=="y" call :ask_required "ask_bot_token" bot_token
if /i "!tem_bot!"=="si" call :ask_required "ask_bot_token" bot_token

(
echo [db]
echo data-source = "!db_url!"
echo.
echo [jwt]
echo secret = "!jwt_secret!"
echo.
echo [tg]
echo app-id = !app_id!
echo app-hash = "!app_hash!"
if defined redis_url (
    echo.
    echo [redis]
    echo url = "!redis_url!"
)
if defined bot_token (
    echo.
    echo [telegram.bot]
    echo token = "!bot_token!"
)
) > "%CONFIG_FILE%"

if exist "%CONFIG_FILE%" (
    call :log_msg "config_created_ok" "OK"
) else (
    call :log_msg "config_created_fail" "ERROR"
    goto fatal
)

:first_time_extras
if not exist "%MODE_FILE%" (
    echo.
    call :print_msg "before_mode_define"
    call :configure_service_mode
)

if not exist "%LAUNCHER_FILE%" (
    echo.
    call :ask_yes_no "create_desktop_icon_now"
    if /i "!ANSWER!"=="Y" (
        call :create_update_start_launcher
        call :create_desktop_shortcut
    ) else (
        call :log_msg "shortcut_skip_now" "INFO"
    )
)

goto menu

:: =========================================================
:: MENU
:: =========================================================
:menu
if exist "%MODE_FILE%" call :load_service_mode
if exist "%SETTINGS_FILE%" call :load_settings

echo.
echo ==================================================
call :print_msg "menu_title"
echo ==================================================
call :print_msg "menu_run_local"
call :print_msg "menu_run_ngrok"
call :print_msg "menu_run_cf"
call :print_msg "menu_reconfig"
call :print_msg "menu_headless"
call :print_msg "menu_folder"
call :print_msg "menu_log"
call :print_msg "menu_shortcut"
call :print_msg "menu_update"
call :print_msg "menu_mode"
call :print_msg "menu_port"
call :print_msg "menu_port_status"
call :print_msg "menu_paths"
call :print_msg "menu_exit"
echo ==================================================
if "!SERVICE_MODE!"=="1" (
    call :print_msg "mode_current_service"
) else (
    call :print_msg "mode_current_normal"
)
call :print_msg "current_port"
echo ==================================================
call :prompt_text "menu_choose" escolha

if "%escolha%"=="1" goto run_local
if "%escolha%"=="2" goto run_ngrok
if "%escolha%"=="3" goto run_cloudflare
if "%escolha%"=="4" goto reconfig
if "%escolha%"=="5" goto run_headless
if "%escolha%"=="6" goto open_folder
if "%escolha%"=="7" goto view_log
if "%escolha%"=="8" goto create_shortcut_menu
if "%escolha%"=="9" goto only_update
if "%escolha%"=="10" goto configure_service_mode
if "%escolha%"=="11" goto change_port
if "%escolha%"=="12" goto show_port_status
if "%escolha%"=="13" goto show_selected_paths
if "%escolha%"=="0" goto end_ok

call :log_msg "invalid_option" "WARN"
call :print_msg "invalid_option_print"
goto menu

:: =========================================================
:: EXECUCOES
:: =========================================================
:run_local
call :pre_run_guard
if errorlevel 1 goto menu
call :etapa "EXEC" "exec_local"
echo.
call :print_msg "tip_local_1"
call :print_msg "tip_local_2"
echo.
call :log_sub "URL: http://localhost:%PORTA%"
call :log_last_msg "starting_app" "INFO"
call :run_teldrive_logged "LOCAL"
echo.
call :print_msg "process_finished"
call :ask_open_log
pause
goto menu

:run_ngrok
call :pre_run_guard
if errorlevel 1 goto menu
call :etapa "EXEC" "exec_ngrok"
echo.
call :print_msg "tip_ngrok_1"
call :print_msg "tip_ngrok_2"
echo.
call :ensure_ngrok
if errorlevel 1 goto menu
echo.
call :print_msg "ngrok_other_window"
echo     "%TELDRIVE_DIR%\ngrok.exe" http %PORTA%
echo.
call :run_teldrive_logged "NGROK"
echo.
call :ask_open_log
pause
goto menu

:run_cloudflare
call :pre_run_guard
if errorlevel 1 goto menu
call :etapa "EXEC" "exec_cloudflare"
echo.
call :print_msg "tip_cf_1"
call :print_msg "tip_cf_2"
echo.
call :ensure_cloudflared
if errorlevel 1 goto menu
echo.
call :print_msg "cf_other_window"
echo     "%TELDRIVE_DIR%\cloudflared.exe" tunnel --url http://localhost:%PORTA%
echo.
call :run_teldrive_logged "CLOUDFLARE"
echo.
call :ask_open_log
pause
goto menu

:reconfig
if exist "%CONFIG_FILE%" (
    del /f /q "%CONFIG_FILE%" >nul 2>&1
    call :log_msg "config_removed_recreate" "INFO"
)
goto check_config

:run_headless
call :pre_run_guard
if errorlevel 1 goto menu
call :etapa "EXEC" "exec_headless"
echo.
call :print_msg "tip_headless_1"
call :print_msg "tip_headless_2"
echo.
call :log_sub_msg "headless_example"
call :log_last_msg "headless_starting" "INFO"
start "Teldrive Headless" cmd /c ""%~f0" __run_logged %LANG% %PORTA% HEADLESS"
echo.
call :print_msg "headless_started_other_window"
call :ask_open_log
pause
goto menu

:open_folder
start "" "%TELDRIVE_DIR%"
call :log_msg "folder_opened" "INFO"
goto menu

:view_log
echo.
echo ================= INICIO DO LOG =================
if exist "%LOGFILE%" (
    type "%LOGFILE%"
) else (
    call :print_msg "no_log_found"
)
echo ================== FIM DO LOG ===================
pause
goto menu

:create_shortcut_menu
call :create_update_start_launcher
call :create_desktop_shortcut
pause
goto menu

:only_update
call :etapa "UPDATE" "update_title"
if not exist "%TELDRIVE_DIR%\.git" (
    call :log_last_msg "project_not_cloned" "ERROR"
    call :ask_open_log
    pause
    goto menu
)
pushd "%TELDRIVE_DIR%"
git pull >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    call :log_last_msg "repo_update_fail" "WARN"
) else (
    call :log_sub_msg "repo_updated"
)
popd
call :update_project_deps
call :ask_open_log
pause
goto menu

:change_port
call :etapa "PORT" "change_port_title"
call :print_msg "change_port_hint"
call :prompt_text "change_port_prompt" NEW_PORT
if not defined NEW_PORT goto menu
set "BADCHAR="
for /f "delims=0123456789" %%A in ("!NEW_PORT!") do set "BADCHAR=%%A"
if defined BADCHAR (
    set "BADCHAR="
    call :print_msg "invalid_port"
    pause
    goto menu
)
if !NEW_PORT! LSS 1 (
    call :print_msg "invalid_port"
    pause
    goto menu
)
if !NEW_PORT! GTR 65535 (
    call :print_msg "invalid_port"
    pause
    goto menu
)
set "PORTA=!NEW_PORT!"
call :save_settings
call :create_update_start_launcher
call :log_msg "port_changed_ok" "INFO"
call :print_msg "port_changed_ok"
pause
goto menu

:show_port_status
call :etapa "PORT" "show_port_status_title"
call :check_port_only
if "!PORT_IN_USE!"=="1" (
    call :print_msg "port_status_busy"
    call :show_port_details
) else (
    call :print_msg "port_status_free"
)
pause
goto menu

:show_selected_paths
echo.
echo ==================================================
call :print_msg "paths_title"
echo ==================================================
if exist "%TELDRIVE_DIR%" echo Teldrive: %TELDRIVE_DIR%
if exist "%CONFIG_FILE%" echo config.toml: %CONFIG_FILE%
if exist "%LOGFILE%" echo Log: %LOGFILE%
if exist "%LAUNCHER_FILE%" echo Launcher: %LAUNCHER_FILE%
if exist "%ProgramFiles%\Git\cmd\git.exe" echo Git: %ProgramFiles%\Git\cmd\git.exe
if exist "%ProgramFiles%\Go\bin\go.exe" echo Go: %ProgramFiles%\Go\bin\go.exe
if exist "%TELDRIVE_DIR%\ngrok.exe" echo Ngrok: %TELDRIVE_DIR%\ngrok.exe
if exist "%TELDRIVE_DIR%\cloudflared.exe" echo Cloudflared: %TELDRIVE_DIR%\cloudflared.exe
echo ==================================================
pause
goto menu

:pre_run_guard
call :check_running_teldrive
if "!TELDRIVE_RUNNING!"=="1" (
    call :handle_running_instance
    if errorlevel 1 exit /b 1
)
exit /b 0

:: =========================================================
:: CHECKS
:: =========================================================
:check_admin
net session >nul 2>&1
if errorlevel 1 (
    call :log_sub_msg "not_admin"
    call :log_last_msg "install_may_fail" "WARN"
    call :ask_yes_no "continue_anyway"
    if /i "!ANSWER!"=="N" (
        call :log_msg "cancel_no_admin" "WARN"
        exit /b 1
    )
) else (
    call :log_last_msg "admin_detected" "OK"
)
exit /b 0

:check_internet
ping 8.8.8.8 -n 1 >nul
if errorlevel 1 (
    call :log_last_msg "no_internet" "ERROR"
    echo.
    call :print_msg "connect_internet_retry"
    call :ask_open_log
    pause
    exit /b 1
)
call :log_last_msg "internet_ok" "OK"
exit /b 0

:find_git
set "GIT_READY=0"
if exist "%GIT_EXE%" (
    set "GIT_READY=1"
    goto :eof
)
for /f "delims=" %%I in ('where git 2^>nul') do (
    set "GIT_EXE=%%I"
    set "GIT_READY=1"
    goto :eof
)
goto :eof

:find_go
set "GO_READY=0"
if exist "%GO_EXE%" (
    set "GO_READY=1"
    goto :eof
)
for /f "delims=" %%I in ('where go 2^>nul') do (
    set "GO_EXE=%%I"
    set "GO_READY=1"
    goto :eof
)
goto :eof

:ensure_git
call :find_git
if "!GIT_READY!"=="1" (
    set "GIT_VER="
    for /f "delims=" %%G in ('"%GIT_EXE%" --version 2^>nul') do set "GIT_VER=%%G"
    if defined GIT_VER (
        call :log_sub_msg "git_installed"
        call :log_last "!GIT_VER!" "OK"
        set "PATH=%ProgramFiles%\Git\cmd;%PATH%"
        exit /b 0
    )
    call :log_sub_msg "git_found_but_broken"
    call :log_last_msg "git_config_invalid" "ERROR"
    exit /b 1
)
call :log_sub_msg "git_not_found"
call :log_sub_msg "git_downloading"
call :download_file "%URL_GIT%" "%BASE_DIR%git-installer.exe" "Git"
if errorlevel 1 exit /b 1
call :log_sub_msg "git_installing"
start /wait "" "%BASE_DIR%git-installer.exe" /VERYSILENT /NORESTART /NOCANCEL /SP- /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" >> "%LOGFILE%" 2>&1
del /f /q "%BASE_DIR%git-installer.exe" >nul 2>&1
call :find_git
if "!GIT_READY!"=="1" (
    call :log_last_msg "git_installed_ok" "OK"
    set "PATH=%ProgramFiles%\Git\cmd;%PATH%"
    exit /b 0
)
call :log_last_msg "git_install_fail" "ERROR"
exit /b 1

:ensure_go
call :find_go
if "!GO_READY!"=="1" (
    set "GO_VER="
    for /f "delims=" %%G in ('"%GO_EXE%" version 2^>nul') do set "GO_VER=%%G"
    if defined GO_VER (
        call :log_sub_msg "go_installed"
        call :log_last "!GO_VER!" "OK"
        set "PATH=%ProgramFiles%\Go\bin;%PATH%"
        exit /b 0
    )
)
call :log_sub_msg "go_not_found"
call :log_sub_msg "go_downloading"
call :download_file "%URL_GO%" "%BASE_DIR%go-installer.msi" "Go"
if errorlevel 1 exit /b 1
call :log_sub_msg "go_installing"
msiexec /i "%BASE_DIR%go-installer.msi" /quiet /norestart >> "%LOGFILE%" 2>&1
del /f /q "%BASE_DIR%go-installer.msi" >nul 2>&1
call :find_go
if "!GO_READY!"=="1" (
    call :log_last_msg "go_installed_ok" "OK"
    set "PATH=%ProgramFiles%\Go\bin;%PATH%"
    exit /b 0
)
call :log_last_msg "go_install_fail" "ERROR"
exit /b 1

:ensure_ngrok
if exist "%TELDRIVE_DIR%\ngrok.exe" (
    call :log_last_msg "ngrok_already_ready" "OK"
    exit /b 0
)
call :log_sub_msg "ngrok_not_found"
call :log_sub_msg "ngrok_downloading"
call :download_file "%URL_NGROK%" "%BASE_DIR%ngrok.zip" "Ngrok"
if errorlevel 1 exit /b 1
call :log_sub_msg "ngrok_extracting"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force '%BASE_DIR%ngrok.zip' '%TELDRIVE_DIR%'" >> "%LOGFILE%" 2>&1
del /f /q "%BASE_DIR%ngrok.zip" >nul 2>&1
if exist "%TELDRIVE_DIR%\ngrok.exe" (
    call :log_last_msg "ngrok_ready" "OK"
    exit /b 0
)
call :log_last_msg "download_fail" "ERROR"
exit /b 1

:ensure_cloudflared
if exist "%TELDRIVE_DIR%\cloudflared.exe" (
    call :log_last_msg "cf_already_ready" "OK"
    exit /b 0
)
call :log_sub_msg "cf_not_found"
call :log_sub_msg "cf_downloading"
call :download_file "%URL_CLOUDFLARED%" "%TELDRIVE_DIR%\cloudflared.exe" "Cloudflared"
if errorlevel 1 exit /b 1
if exist "%TELDRIVE_DIR%\cloudflared.exe" (
    call :log_last_msg "cf_ready" "OK"
    exit /b 0
)
call :log_last_msg "download_fail" "ERROR"
exit /b 1

:: =========================================================
:: REPO
:: =========================================================
:detect_existing_installation
set "INSTALL_MODE=UPDATE"
if not exist "%TELDRIVE_DIR%" goto :eof
if not exist "%TELDRIVE_DIR%\.git" goto :eof
echo.
call :print_msg "existing_install_title"
call :print_msg "existing_install_1"
call :print_msg "existing_install_2"
call :print_msg "existing_install_3"
call :print_msg "existing_install_4"
call :prompt_text "menu_choose" install_choice
if "%install_choice%"=="1" set "INSTALL_MODE=UPDATE"
if "%install_choice%"=="2" set "INSTALL_MODE=KEEP"
if "%install_choice%"=="3" set "INSTALL_MODE=CLEAN"
if "%install_choice%"=="4" exit /b 1
if not defined install_choice set "INSTALL_MODE=UPDATE"
goto :eof

:prepare_repo
if not exist "%TELDRIVE_DIR%\.git" (
    call :log_sub_msg "project_not_installed"
    call :log_sub_msg "cloning_repo"
    git clone "%URL_REPO%" "%TELDRIVE_DIR%" >> "%LOGFILE%" 2>&1
    if errorlevel 1 (
        call :log_last_msg "clone_fail" "ERROR"
        exit /b 1
    )
    call :log_last_msg "clone_ok" "OK"
    exit /b 0
)

if /i "!INSTALL_MODE!"=="UPDATE" (
    call :log_sub_msg "project_already_installed"
    call :log_sub_msg "updating_repo"
    pushd "%TELDRIVE_DIR%"
    git pull >> "%LOGFILE%" 2>&1
    if errorlevel 1 (
        call :log_last_msg "repo_update_warn" "WARN"
    ) else (
        call :log_last_msg "repo_update_ok" "OK"
    )
    popd
    exit /b 0
)

if /i "!INSTALL_MODE!"=="KEEP" (
    call :backup_current_config_if_exists
    call :reinstall_project_keep_config
    exit /b %errorlevel%
)

if /i "!INSTALL_MODE!"=="CLEAN" (
    call :reinstall_project_clean
    exit /b %errorlevel%
)

exit /b 0

:backup_current_config_if_exists
if exist "%CONFIG_FILE%" copy /y "%CONFIG_FILE%" "%TEMP_CONFIG_BACKUP%" >nul 2>&1
goto :eof

:reinstall_project_keep_config
call :log_msg "reinstall_keep_start" "INFO"
if exist "%TELDRIVE_DIR%" rmdir /S /Q "%TELDRIVE_DIR%" >nul 2>&1
git clone "%URL_REPO%" "%TELDRIVE_DIR%" >> "%LOGFILE%" 2>&1
if errorlevel 1 exit /b 1
if exist "%TEMP_CONFIG_BACKUP%" (
    copy /y "%TEMP_CONFIG_BACKUP%" "%CONFIG_FILE%" >nul 2>&1
    del /f /q "%TEMP_CONFIG_BACKUP%" >nul 2>&1
)
exit /b 0

:reinstall_project_clean
call :log_msg "reinstall_clean_start" "INFO"
if exist "%TEMP_CONFIG_BACKUP%" del /f /q "%TEMP_CONFIG_BACKUP%" >nul 2>&1
if exist "%TELDRIVE_DIR%" rmdir /S /Q "%TELDRIVE_DIR%" >nul 2>&1
git clone "%URL_REPO%" "%TELDRIVE_DIR%" >> "%LOGFILE%" 2>&1
if errorlevel 1 exit /b 1
exit /b 0

:update_project_deps
cd /d "%TELDRIVE_DIR%"
if exist go.mod (
    call :log_sub_msg "gomod_tidy"
    go mod tidy >> "%LOGFILE%" 2>&1
    if errorlevel 1 (
        call :log_last_msg "gomod_tidy_fail" "WARN"
        exit /b 0
    )
    call :log_sub_msg "gomod_download"
    go mod download >> "%LOGFILE%" 2>&1
    if errorlevel 1 (
        call :log_last_msg "gomod_download_fail" "WARN"
    ) else (
        call :log_last_msg "deps_updated_ok" "OK"
    )
) else (
    call :log_last_msg "gomod_not_found" "WARN"
)
exit /b 0

:: =========================================================
:: PROCESSO / PORTA
:: =========================================================
:check_port_only
set "PORT_IN_USE=0"
set "PORT_PID="
set "PORT_PROC_NAME="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%PORTA% .*LISTENING"') do (
    set "PORT_IN_USE=1"
    set "PORT_PID=%%P"
    goto port_found
)
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%PORTA%"') do (
    set "PORT_IN_USE=1"
    set "PORT_PID=%%P"
    goto port_found
)
goto :eof
:port_found
for /f "tokens=1 delims=," %%A in ('tasklist /FI "PID eq !PORT_PID!" /FO CSV /NH 2^>nul') do set "PORT_PROC_NAME=%%~A"
goto :eof

:show_port_details
call :check_port_only
if "!PORT_IN_USE!"=="0" goto :eof
echo.
if /i "%LANG%"=="pt" echo 🔎 Processo usando a porta !PORTA!:
if /i "%LANG%"=="en" echo 🔎 Process using port !PORTA!:
if /i "%LANG%"=="es" echo 🔎 Proceso usando el puerto !PORTA!:
echo    PID: !PORT_PID!
if defined PORT_PROC_NAME (
    if /i "%LANG%"=="pt" echo    Nome: !PORT_PROC_NAME!
    if /i "%LANG%"=="en" echo    Name: !PORT_PROC_NAME!
    if /i "%LANG%"=="es" echo    Nombre: !PORT_PROC_NAME!
)
call :log "Port !PORTA! in use by PID !PORT_PID! !PORT_PROC_NAME!" "INFO"
goto :eof

:check_running_teldrive
set "TELDRIVE_RUNNING=0"
set "RUN_PID="
set "RUN_PROC_NAME="
call :check_port_only

tasklist /FI "IMAGENAME eq teldrive.exe" 2>nul | find /I "teldrive.exe" >nul
if not errorlevel 1 (
    set "TELDRIVE_RUNNING=1"
    call :log_msg "detected_teldrive_exe" "WARN"
    goto :eof
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $p = Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^teldrive(\.exe)?$' -or $_.CommandLine -match 'cmd\\teldrive\\main\.go' }; if($p){ exit 0 } else { exit 1 } } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 (
    set "TELDRIVE_RUNNING=1"
    call :log_msg "detected_teldrive_process" "WARN"
    goto :eof
)

if "!PORT_IN_USE!"=="1" (
    set "TELDRIVE_RUNNING=1"
    set "RUN_PID=!PORT_PID!"
    set "RUN_PROC_NAME=!PORT_PROC_NAME!"
    call :log_msg "detected_port_possible_instance" "WARN"
)
goto :eof

:handle_running_instance
call :log_last_msg "running_found" "WARN"
echo.
call :print_msg "running_detected_machine"
if defined RUN_PID echo    PID: !RUN_PID!
if defined RUN_PROC_NAME echo    PROC: !RUN_PROC_NAME!
if "!PORT_IN_USE!"=="1" call :show_port_details
echo.
call :print_msg "running_menu_title"
call :print_msg "running_menu_1"
call :print_msg "running_menu_2"
call :print_msg "running_menu_3"
call :prompt_text "menu_choose" run_choice

if "%run_choice%"=="1" exit /b 0
if "%run_choice%"=="2" (
    call :try_kill_running_teldrive
    if "!TELDRIVE_RUNNING!"=="0" (
        call :print_msg "running_kill_ok"
        exit /b 0
    ) else (
        call :print_msg "running_kill_fail"
        pause
        exit /b 1
    )
)
call :print_msg "running_cancelled"
exit /b 1

:try_kill_running_teldrive
taskkill /F /IM teldrive.exe >nul 2>&1
if "!PORT_IN_USE!"=="1" if defined PORT_PID taskkill /F /PID !PORT_PID! >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^teldrive(\.exe)?$' -or $_.CommandLine -match 'cmd\\teldrive\\main\.go' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }" >nul 2>&1
timeout /t 2 >nul
call :check_running_teldrive
goto :eof

:: =========================================================
:: CONFIG REUSE
:: =========================================================
:find_existing_config
set "FOUND_CONFIG="
for %%F in ("%CONFIG_FILE%" "%BASE_DIR%\config.toml") do (
    if not defined FOUND_CONFIG if exist "%%~F" set "FOUND_CONFIG=%%~F"
)
if not defined FOUND_CONFIG (
    for %%F in ("%TELDRIVE_DIR%\config_backup_*.toml" "%BASE_DIR%\config_backup_*.toml") do (
        if not defined FOUND_CONFIG if exist "%%~F" set "FOUND_CONFIG=%%~F"
    )
)
goto :eof

:: =========================================================
:: RUN LOGADO
:: =========================================================
:cli_run_logged
if not "%~2"=="" set "LANG=%~2"
if not "%~3"=="" set "PORTA=%~3"
call :detect_date_mode
cd /d "%TELDRIVE_DIR%"
call :run_teldrive_logged "%~4"
exit /b %ERRORLEVEL%

:run_teldrive_logged
set "RUN_MODE=%~1"
call :log "==================================================" "INFO"
call :log "TELDRIVE START | MODE=%RUN_MODE% | PORT=%PORTA%" "INFO"
call :log "==================================================" "INFO"
go run cmd\teldrive\main.go >> "%LOGFILE%" 2>&1
set "APP_EXIT=%ERRORLEVEL%"
if not "%APP_EXIT%"=="0" (
    call :log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" "ERROR"
    call :log "TELDRIVE CRASH DETECTED | EXITCODE=%APP_EXIT% | MODE=%RUN_MODE% | PORT=%PORTA%" "ERROR"
    call :log "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" "ERROR"
    call :print_msg "crash_detected"
    call :print_msg "crash_check_log"
    exit /b %APP_EXIT%
)
call :log "TELDRIVE FINISHED OK | MODE=%RUN_MODE% | PORT=%PORTA%" "OK"
call :print_msg "app_finished_ok"
exit /b 0

:: =========================================================
:: SETTINGS / MODE / LAUNCHER
:: =========================================================
:configure_service_mode
cls
echo.
echo ==================================================
call :print_msg "service_title"
echo ==================================================
call :print_msg "service_line1"
call :print_msg "service_line2"
echo.
call :print_msg "service_adv"
call :print_msg "service_adv1"
call :print_msg "service_adv2"
call :print_msg "service_adv3"
echo.
call :print_msg "service_warn"
call :print_msg "service_warn1"
call :print_msg "service_warn2"
call :print_msg "service_warn3"
echo.
call :ask_yes_no "service_question"
if /i "!ANSWER!"=="N" (
    if not exist "%TELDRIVE_DIR%" mkdir "%TELDRIVE_DIR%" >nul 2>&1
    > "%MODE_FILE%" echo SERVICE_MODE=0
    set "SERVICE_MODE=0"
    call :log_msg "service_mode_log_normal" "INFO"
    echo.
    call :print_msg "service_mode_normal_ok"
) else (
    if not exist "%TELDRIVE_DIR%" mkdir "%TELDRIVE_DIR%" >nul 2>&1
    > "%MODE_FILE%" echo SERVICE_MODE=1
    set "SERVICE_MODE=1"
    call :log_msg "service_mode_log_service" "INFO"
    echo.
    call :print_msg "service_mode_service_ok"
)
pause
goto :eof

:load_service_mode
for /f "tokens=2 delims==" %%A in ('type "%MODE_FILE%" 2^>nul ^| findstr /B /I "SERVICE_MODE="') do set "SERVICE_MODE=%%A"
if not defined SERVICE_MODE set "SERVICE_MODE=0"
goto :eof

:save_settings
if not exist "%TELDRIVE_DIR%" mkdir "%TELDRIVE_DIR%" >nul 2>&1
(
    echo PORT=%PORTA%
) > "%SETTINGS_FILE%"
goto :eof

:load_settings
for /f "tokens=1,2 delims==" %%A in ('type "%SETTINGS_FILE%" 2^>nul') do (
    if /i "%%A"=="PORT" set "PORTA=%%B"
)
if not defined PORTA set "PORTA=8080"
goto :eof

:create_update_start_launcher
call :etapa "EXTRA" "shortcut_step"
(
    echo @echo off
    echo setlocal EnableExtensions EnableDelayedExpansion
    echo chcp 65001 ^>nul
    echo title Teldrive - Update and Start
    echo color 0B
    echo cls
    echo set "LANG=%LANG%"
    echo set "TELDRIVE_DIR=%TELDRIVE_DIR%"
    echo set "LOGFILE=%LOGFILE%"
    echo set "PORTA=%PORTA%"
    echo cd /d "%%TELDRIVE_DIR%%"
    echo if not exist "%%TELDRIVE_DIR%%\.git" ^(
    echo   echo Teldrive project not found.
    echo   pause
    echo   exit /b 1
    echo ^)
    echo git pull ^>^> "%%LOGFILE%%" 2^>^&1
    echo if exist go.mod ^(
    echo   go mod tidy ^>^> "%%LOGFILE%%" 2^>^&1
    echo   go mod download ^>^> "%%LOGFILE%%" 2^>^&1
    echo ^)
    echo tasklist /FI "IMAGENAME eq teldrive.exe" 2^>nul ^| find /I "teldrive.exe" ^>nul
    echo if not errorlevel 1 goto already_running
    echo start "Teldrive App" cmd /c ""%~f0" __run_logged %%LANG%% %%PORTA%% DESKTOP"
    echo if /i "%%LANG%%"=="pt" echo ✅ Atualizacao concluida e Teldrive iniciado.
    echo if /i "%%LANG%%"=="en" echo ✅ Update finished and Teldrive started.
    echo if /i "%%LANG%%"=="es" echo ✅ Actualizacion finalizada y Teldrive iniciado.
    echo if /i "%%LANG%%"=="pt" echo 📄 Deseja abrir o log agora? [S/N]
    echo if /i "%%LANG%%"=="es" echo 📄 Desea abrir el log ahora? [S/N]
    echo if /i "%%LANG%%"=="en" echo 📄 Would you like to open the log now? [Y/N]
    echo if /i "%%LANG%%"=="pt" choice /c SN /n
    echo if /i "%%LANG%%"=="es" choice /c SN /n
    echo if /i "%%LANG%%"=="en" choice /c YN /n
    echo if errorlevel 2 exit /b 0
    echo if exist "%%LOGFILE%%" start "" notepad "%%LOGFILE%%"
    echo exit /b 0
    echo :already_running
    echo if /i "%%LANG%%"=="pt" echo ⚠️ O Teldrive ja esta em execucao.
    echo if /i "%%LANG%%"=="en" echo ⚠️ Teldrive is already running.
    echo if /i "%%LANG%%"=="es" echo ⚠️ Teldrive ya esta en ejecucion.
    echo if /i "%%LANG%%"=="pt" echo 📄 Deseja abrir o log? [S/N]
    echo if /i "%%LANG%%"=="es" echo 📄 Desea abrir el log? [S/N]
    echo if /i "%%LANG%%"=="en" echo 📄 Would you like to open the log? [Y/N]
    echo if /i "%%LANG%%"=="pt" choice /c SN /n
    echo if /i "%%LANG%%"=="es" choice /c SN /n
    echo if /i "%%LANG%%"=="en" choice /c YN /n
    echo if errorlevel 2 exit /b 0
    echo if exist "%%LOGFILE%%" start "" notepad "%%LOGFILE%%"
) > "%LAUNCHER_FILE%"
if exist "%LAUNCHER_FILE%" (
    call :log "Launcher created: %LAUNCHER_FILE%" "OK"
    call :print_msg "shortcut_created_ok"
) else (
    call :log "Failed to create launcher" "ERROR"
    call :print_msg "shortcut_created_fail"
)
goto :eof

:create_desktop_shortcut
call :etapa "EXTRA" "desktop_step"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$W=New-Object -ComObject WScript.Shell; $Desktop=[Environment]::GetFolderPath('Desktop'); $S=$W.CreateShortcut($Desktop + '\Teldrive - Atualizar e Iniciar.lnk'); $S.TargetPath='%LAUNCHER_FILE%'; $S.WorkingDirectory='%BASE_DIR%'; $S.IconLocation='%SystemRoot%\System32\shell32.dll,220'; $S.Description='Update and start Teldrive'; $S.Save()" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    call :log "Failed to create desktop icon" "ERROR"
    call :print_msg "desktop_fail"
) else (
    call :log "Desktop icon created" "OK"
    call :print_msg "desktop_ok"
)
goto :eof

:show_finish_summary
echo.
echo ==================================================
call :print_msg "paths_title"
echo ==================================================
if exist "%TELDRIVE_DIR%" echo Teldrive: %TELDRIVE_DIR%
if exist "%CONFIG_FILE%" echo config.toml: %CONFIG_FILE%
if exist "%LOGFILE%" echo Log: %LOGFILE%
if exist "%LAUNCHER_FILE%" echo Launcher: %LAUNCHER_FILE%
if exist "%ProgramFiles%\Git\cmd\git.exe" echo Git: %ProgramFiles%\Git\cmd\git.exe
if exist "%ProgramFiles%\Go\bin\go.exe" echo Go: %ProgramFiles%\Go\bin\go.exe
if exist "%TELDRIVE_DIR%\ngrok.exe" echo Ngrok: %TELDRIVE_DIR%\ngrok.exe
if exist "%TELDRIVE_DIR%\cloudflared.exe" echo Cloudflared: %TELDRIVE_DIR%\cloudflared.exe
echo ==================================================
goto :eof

:: =========================================================
:: FIM / ERRO
:: =========================================================
:end_ok
call :log_msg "installer_closed_user" "INFO"
echo.
call :print_msg "process_finished_ok"
echo.
call :show_finish_summary
call :ask_open_log
echo.
call :print_msg "closed_ok"
exit /b 0

:fatal
echo.
call :print_msg "fatal_error"
call :print_msg "check_log_here"
echo %LOGFILE%
call :log "INSTALLER FATAL ERROR" "ERROR"
call :log_msg "fatal_log_msg" "ERROR"
call :show_finish_summary
call :ask_open_log
pause
exit /b 1

:: =========================================================
:: UI / LOG
:: =========================================================
:banner
echo.
echo ==================================================
call :print_msg "welcome_title"
call :print_msg "welcome_version"
call :print_msg "welcome_sub1"
call :print_msg "welcome_sub2"
call :print_msg "welcome_sub3"
echo ==================================================
echo.
goto :eof

:select_language
:select_language_loop
echo ==================================================
echo 🌍 LANGUAGE / IDIOMA / LENGUAJE
echo ==================================================
echo.
call :print_msg "ask_language"
echo.
call :print_msg "lang_pt"
call :print_msg "lang_en"
call :print_msg "lang_es"
echo.
set "lang_choice="
set /p "lang_choice=👉 "
if "%lang_choice%"=="1" set "LANG=pt"
if "%lang_choice%"=="2" set "LANG=en"
if "%lang_choice%"=="3" set "LANG=es"
if "%lang_choice%"=="1" goto language_ok
if "%lang_choice%"=="2" goto language_ok
if "%lang_choice%"=="3" goto language_ok
echo.
call :print_msg "invalid_language"
echo.
goto select_language_loop
:language_ok
echo.
call :print_msg "lang_selected"
timeout /t 1 >nul
cls
goto :eof

:print_msg
call :msg %~1
echo !MSG!
goto :eof

:prompt_text
call :msg %~1
set "%~2="
set /p "%~2=!MSG! "
goto :eof

:ask_yes_no
call :msg %~1
echo.
echo !MSG!
if /i "%LANG%"=="pt" echo [S/N]
if /i "%LANG%"=="es" echo [S/N]
if /i "%LANG%"=="en" echo [Y/N]
if /i "%LANG%"=="pt" (
    choice /c SN /n
    if errorlevel 2 (set "ANSWER=N") else set "ANSWER=Y"
    echo.
    goto :eof
)
if /i "%LANG%"=="es" (
    choice /c SN /n
    if errorlevel 2 (set "ANSWER=N") else set "ANSWER=Y"
    echo.
    goto :eof
)
choice /c YN /n
if errorlevel 2 (set "ANSWER=N") else set "ANSWER=Y"
echo.
goto :eof

:etapa
echo.
echo --------------------------------------------------
call :msg %~2
if /i "%LANG%"=="pt" (
    echo 🔹 [PASSO %~1] !MSG!
    echo --------------------------------------------------
    call :log "[PASSO %~1] !MSG!" "INFO"
    goto :eof
)
if /i "%LANG%"=="es" (
    echo 🔹 [PASO %~1] !MSG!
    echo --------------------------------------------------
    call :log "[PASO %~1] !MSG!" "INFO"
    goto :eof
)
echo 🔹 [STEP %~1] !MSG!
echo --------------------------------------------------
call :log "[STEP %~1] !MSG!" "INFO"
goto :eof

:detect_date_mode
set "DATE_MODE=LOCAL"
set "RAW_DATE=%date%"
if "%RAW_DATE:~2,1%"=="/" if "%RAW_DATE:~5,1%"=="/" goto :eof
set "DATE_MODE=INTL"
echo.
call :print_msg "date_warn_nonlocal"
goto :eof

:make_log_datetime
set "HORA=%time:~0,8%"
set "HORA=%HORA: =0%"
if /i "%DATE_MODE%"=="INTL" (
    set "DATAHORA=%HORA% %date%"
    goto :eof
)
set "DIA=%date:~0,2%"
set "MES=%date:~3,2%"
set "ANO=%date:~6,4%"
if /i "%LANG%"=="en" (
    set "DATAHORA=%HORA% %MES%-%DIA%-%ANO%"
    goto :eof
)
set "DATAHORA=%HORA% %DIA%-%MES%-%ANO%"
goto :eof

:log
call :make_log_datetime
set "MSGTXT=%~1"
set "NIVEL=%~2"
if "%NIVEL%"=="" set "NIVEL=INFO"
set "LVL_ICON=⚠️"
if /i "%NIVEL%"=="WARN" set "LVL_ICON=❌"
if /i "%NIVEL%"=="ERROR" set "LVL_ICON=❌"
if /i "%NIVEL%"=="OK" set "LVL_ICON=✅"
set "NIVEL_TXT=%NIVEL%"
if /i "%LANG%"=="pt" (
    if /i "%NIVEL%"=="WARN" set "NIVEL_TXT=AVISO"
    if /i "%NIVEL%"=="ERROR" set "NIVEL_TXT=ERRO"
    if /i "%NIVEL%"=="OK" set "NIVEL_TXT=SUCESSO"
)
if /i "%LANG%"=="es" (
    if /i "%NIVEL%"=="WARN" set "NIVEL_TXT=AVISO"
    if /i "%NIVEL%"=="OK" set "NIVEL_TXT=EXITO"
)
if /i "%LANG%"=="en" if /i "%NIVEL%"=="OK" set "NIVEL_TXT=SUCCESS"
echo [%DATAHORA%] [%NIVEL_TXT% %LVL_ICON%] %MSGTXT%
echo [%DATAHORA%] [%NIVEL_TXT% %LVL_ICON%] %MSGTXT%>>"%LOGFILE%"
goto :eof

:log_msg
call :msg %~1
call :log "!MSG!" "%~2"
goto :eof

:log_sub
set "MSGTXT=%~1"
echo     ├─ %MSGTXT%
echo     ├─ %MSGTXT%>>"%LOGFILE%"
goto :eof

:log_sub_msg
call :msg %~1
call :log_sub "!MSG!"
goto :eof

:log_last
set "MSGTXT=%~1"
set "NIVEL=%~2"
if "%NIVEL%"=="" set "NIVEL=INFO"
set "LVL_ICON=⚠️"
if /i "%NIVEL%"=="WARN" set "LVL_ICON=❌"
if /i "%NIVEL%"=="ERROR" set "LVL_ICON=❌"
if /i "%NIVEL%"=="OK" set "LVL_ICON=✅"
set "NIVEL_TXT=%NIVEL%"
if /i "%LANG%"=="pt" (
    if /i "%NIVEL%"=="WARN" set "NIVEL_TXT=AVISO"
    if /i "%NIVEL%"=="ERROR" set "NIVEL_TXT=ERRO"
    if /i "%NIVEL%"=="OK" set "NIVEL_TXT=SUCESSO"
)
if /i "%LANG%"=="es" (
    if /i "%NIVEL%"=="WARN" set "NIVEL_TXT=AVISO"
    if /i "%NIVEL%"=="OK" set "NIVEL_TXT=EXITO"
)
if /i "%LANG%"=="en" if /i "%NIVEL%"=="OK" set "NIVEL_TXT=SUCCESS"
echo     └─ [%NIVEL_TXT% %LVL_ICON%] %MSGTXT%
echo     └─ [%NIVEL_TXT% %LVL_ICON%] %MSGTXT%>>"%LOGFILE%"
goto :eof

:ask_required
set "%~2="
:ask_required_loop
call :prompt_text "%~1" %~2
if not defined %~2 (
    call :print_msg "required_empty"
    call :log_msg "required_log" "WARN"
    goto ask_required_loop
)
call :log_msg "required_ok" "INFO"
goto :eof

:download_file
set "DL_URL=%~1"
set "DL_OUT=%~2"
set "DL_NAME=%~3"
call :msg download_start
call :log "!MSG! %DL_NAME%" "INFO"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%DL_URL%' -OutFile '%DL_OUT%'" >> "%LOGFILE%" 2>&1
if errorlevel 1 (
    call :msg download_fail
    call :log "!MSG! %DL_NAME%" "ERROR"
    exit /b 1
)
call :msg download_ok
call :log "!MSG! %DL_NAME%" "OK"
exit /b 0

:ask_open_log
echo.
call :print_msg "ask_open_log_title"
call :print_msg "ask_open_log_sub"
call :ask_yes_no "ask_open_log_choice"
if /i "!ANSWER!"=="Y" call :open_log_window
goto :eof

:open_log_window
if exist "%LOGFILE%" (
    start "" notepad "%LOGFILE%"
    call :log_msg "log_opened" "INFO"
) else (
    echo.
    call :print_msg "no_log_found"
)
goto :eof

:: =========================================================
:: MSGS
:: =========================================================
:msg
set "MSG="
if /i "%LANG%"=="pt" goto msg_pt
if /i "%LANG%"=="es" goto msg_es
goto msg_en

:msg_pt
if /i "%~1"=="welcome_title" set "MSG=🚀 %APP_NAME%"
if /i "%~1"=="welcome_version" set "MSG=🏷️ Versao: v%APP_VERSION%"
if /i "%~1"=="welcome_sub1" set "MSG=🛠️ Instalacao guiada do ambiente"
if /i "%~1"=="welcome_sub2" set "MSG=💻 Git + Go + Configuracao + Execucao"
if /i "%~1"=="welcome_sub3" set "MSG=😊 Pronto para deixar seu Teldrive tinindo!"
if /i "%~1"=="ask_language" set "MSG=Qual idioma deseja usar?"
if /i "%~1"=="lang_pt" set "MSG=[1] PT-BR - Portugues (nativo)"
if /i "%~1"=="lang_en" set "MSG=[2] EN - English"
if /i "%~1"=="lang_es" set "MSG=[3] ES - Espanol"
if /i "%~1"=="lang_selected" set "MSG=✅ Idioma definido com sucesso."
if /i "%~1"=="invalid_language" set "MSG=❌ Opcao de idioma invalida."
if /i "%~1"=="date_warn_nonlocal" set "MSG=⚠️ O Windows nao esta em dd/mm/yyyy. O log usara o formato internacional do sistema."
if /i "%~1"=="step_permissions" set "MSG=Verificando permissoes do sistema"
if /i "%~1"=="step_internet" set "MSG=Verificando conexao com a internet"
if /i "%~1"=="step_running_check" set "MSG=Verificando se ja existe outro Teldrive rodando"
if /i "%~1"=="step_dependencies" set "MSG=Verificando dependencias instaladas"
if /i "%~1"=="step_repo" set "MSG=Preparando ou atualizando o repositorio do Teldrive"
if /i "%~1"=="step_project_deps" set "MSG=Atualizando dependencias do projeto"
if /i "%~1"=="step_port" set "MSG=Verificando disponibilidade da porta atual"
if /i "%~1"=="step_config" set "MSG=Criando configuracao inicial"
if /i "%~1"=="not_admin" set "MSG=⚠️ O script nao esta sendo executado como administrador"
if /i "%~1"=="install_may_fail" set "MSG=Algumas instalacoes podem falhar"
if /i "%~1"=="continue_anyway" set "MSG=👉 Deseja continuar mesmo assim?"
if /i "%~1"=="cancel_no_admin" set "MSG=⚠️ Execucao cancelada por falta de privilegios"
if /i "%~1"=="admin_detected" set "MSG=✅ Permissoes administrativas detectadas"
if /i "%~1"=="no_internet" set "MSG=❌ Sem conexao com a internet"
if /i "%~1"=="internet_ok" set "MSG=🌐 Conexao com a internet confirmada"
if /i "%~1"=="connect_internet_retry" set "MSG=❌ Conecte-se a internet e tente novamente."
if /i "%~1"=="running_found" set "MSG=⚠️ Foi encontrada uma instancia do Teldrive em execucao"
if /i "%~1"=="running_not_found" set "MSG=✅ Nenhuma instancia do Teldrive encontrada"
if /i "%~1"=="running_detected_machine" set "MSG=⚠️ Parece que ja existe um Teldrive rodando nesta maquina."
if /i "%~1"=="running_menu_title" set "MSG=Escolha o que deseja fazer com a instancia em execucao:"
if /i "%~1"=="running_menu_1" set "MSG=[1] Continuar mesmo assim"
if /i "%~1"=="running_menu_2" set "MSG=[2] Encerrar o Teldrive atual e continuar"
if /i "%~1"=="running_menu_3" set "MSG=[3] Cancelar"
if /i "%~1"=="running_kill_ok" set "MSG=✅ Processo atual encerrado com sucesso"
if /i "%~1"=="running_kill_fail" set "MSG=❌ Nao foi possivel encerrar o processo atual"
if /i "%~1"=="running_cancelled" set "MSG=⚠️ Operacao cancelada pelo usuario"
if /i "%~1"=="detected_teldrive_exe" set "MSG=⚠️ Detectado processo teldrive.exe em execucao"
if /i "%~1"=="detected_teldrive_process" set "MSG=⚠️ Detectado processo relacionado ao Teldrive em execucao"
if /i "%~1"=="detected_port_possible_instance" set "MSG=⚠️ A porta atual esta em uso; pode haver uma instancia do Teldrive rodando"
if /i "%~1"=="git_installed" set "MSG=🟢 Git ja esta instalado"
if /i "%~1"=="git_not_found" set "MSG=🟡 Git nao encontrado"
if /i "%~1"=="git_downloading" set "MSG=⬇️ Baixando instalador do Git"
if /i "%~1"=="git_installing" set "MSG=⚙️ Executando instalacao silenciosa do Git"
if /i "%~1"=="git_installed_ok" set "MSG=✅ Git instalado com sucesso"
if /i "%~1"=="git_install_fail" set "MSG=❌ Falha ao instalar Git"
if /i "%~1"=="git_found_but_broken" set "MSG=⚠️ Git foi encontrado, mas parece estar com configuracao quebrada"
if /i "%~1"=="git_config_invalid" set "MSG=❌ O arquivo de configuracao do Git parece invalido. Corrija ou reinstale o Git."
if /i "%~1"=="go_installed" set "MSG=🟢 Go ja esta instalado"
if /i "%~1"=="go_not_found" set "MSG=🟡 Go nao encontrado"
if /i "%~1"=="go_downloading" set "MSG=⬇️ Baixando instalador do Go"
if /i "%~1"=="go_installing" set "MSG=⚙️ Executando instalacao silenciosa do Go"
if /i "%~1"=="go_installed_ok" set "MSG=✅ Go instalado com sucesso"
if /i "%~1"=="go_install_fail" set "MSG=❌ Falha ao instalar Go"
if /i "%~1"=="existing_install_title" set "MSG=Foi encontrada uma instalacao anterior do Teldrive."
if /i "%~1"=="existing_install_1" set "MSG=[1] Atualizar esta instalacao"
if /i "%~1"=="existing_install_2" set "MSG=[2] Reinstalar mantendo configuracao"
if /i "%~1"=="existing_install_3" set "MSG=[3] Reinstalar do zero"
if /i "%~1"=="existing_install_4" set "MSG=[4] Cancelar"
if /i "%~1"=="project_not_installed" set "MSG=📦 Projeto ainda nao esta instalado"
if /i "%~1"=="cloning_repo" set "MSG=🌍 Clonando repositorio oficial do Teldrive"
if /i "%~1"=="clone_fail" set "MSG=❌ Falha ao clonar o repositorio"
if /i "%~1"=="clone_ok" set "MSG=✅ Repositorio clonado com sucesso"
if /i "%~1"=="project_already_installed" set "MSG=📁 Projeto ja esta instalado"
if /i "%~1"=="updating_repo" set "MSG=🔄 Atualizando repositorio local"
if /i "%~1"=="repo_update_warn" set "MSG=⚠️ Nao foi possivel atualizar o repositorio, seguindo com arquivos locais"
if /i "%~1"=="repo_update_ok" set "MSG=✅ Repositorio atualizado com sucesso"
if /i "%~1"=="reinstall_keep_start" set "MSG=♻️ Reinstalando o projeto mantendo configuracao"
if /i "%~1"=="reinstall_clean_start" set "MSG=🧹 Reinstalando o projeto do zero"
if /i "%~1"=="config_found" set "MSG=✅ Arquivo config.toml encontrado"
if /i "%~1"=="external_config_found" set "MSG=📄 Foi encontrada uma configuracao anterior:"
if /i "%~1"=="reuse_found_config" set "MSG=Deseja reutilizar essa configuracao encontrada?"
if /i "%~1"=="ask_db_url" set "MSG=Cole a URL do banco PostgreSQL/Neon:"
if /i "%~1"=="ask_app_id" set "MSG=Digite o App ID do Telegram:"
if /i "%~1"=="ask_app_hash" set "MSG=Digite o App Hash do Telegram:"
if /i "%~1"=="ask_jwt_secret" set "MSG=Digite a chave JWT:"
if /i "%~1"=="ask_redis_optional" set "MSG=Digite a URL do Redis (opcional):"
if /i "%~1"=="ask_bot_yesno" set "MSG=Deseja configurar um bot do Telegram? (s/n):"
if /i "%~1"=="ask_bot_token" set "MSG=Digite o token do bot do Telegram:"
if /i "%~1"=="config_created_ok" set "MSG=✅ Arquivo config.toml criado com sucesso"
if /i "%~1"=="config_created_fail" set "MSG=❌ Falha ao criar o arquivo config.toml"
if /i "%~1"=="before_mode_define" set "MSG=💡 Antes de seguir, vamos definir o modo de uso preferido."
if /i "%~1"=="create_desktop_icon_now" set "MSG=🖥️ Deseja criar agora um icone na area de trabalho para atualizar e iniciar o Teldrive?"
if /i "%~1"=="shortcut_skip_now" set "MSG=ℹ️ Usuario optou por nao criar o atalho agora"
if /i "%~1"=="menu_title" set "MSG=🚀 MENU PRINCIPAL - %APP_NAME% v%APP_VERSION%"
if /i "%~1"=="menu_run_local" set "MSG=[1] ▶️ Rodar localmente"
if /i "%~1"=="menu_run_ngrok" set "MSG=[2] 🌍 Rodar com Ngrok"
if /i "%~1"=="menu_run_cf" set "MSG=[3] ☁️ Rodar com Cloudflare Tunnel"
if /i "%~1"=="menu_reconfig" set "MSG=[4] ⚙️ Reconfigurar config.toml"
if /i "%~1"=="menu_headless" set "MSG=[5] 🤖 Rodar em modo headless"
if /i "%~1"=="menu_folder" set "MSG=[6] 📂 Abrir pasta do projeto"
if /i "%~1"=="menu_log" set "MSG=[7] 📜 Ver arquivo de log"
if /i "%~1"=="menu_shortcut" set "MSG=[8] 🖥️ Criar/Recriar atalho da area de trabalho"
if /i "%~1"=="menu_update" set "MSG=[9] 🔄 Atualizar projeto e dependencias"
if /i "%~1"=="menu_mode" set "MSG=[10] ⚙️ Configurar modo de execucao"
if /i "%~1"=="menu_port" set "MSG=[11] 🔌 Alterar porta"
if /i "%~1"=="menu_port_status" set "MSG=[12] 🔍 Verificar porta"
if /i "%~1"=="menu_paths" set "MSG=[13] 📍 Mostrar caminhos salvos"
if /i "%~1"=="menu_exit" set "MSG=[0] 👋 Sair"
if /i "%~1"=="mode_current_service" set "MSG=💡 Modo atual: SERVICO PREFERENCIAL"
if /i "%~1"=="mode_current_normal" set "MSG=💡 Modo atual: NORMAL"
if /i "%~1"=="current_port" set "MSG=🔌 Porta atual: %PORTA%"
if /i "%~1"=="menu_choose" set "MSG=👉 Escolha uma opcao:"
if /i "%~1"=="invalid_option" set "MSG=⚠️ Opcao invalida informada"
if /i "%~1"=="invalid_option_print" set "MSG=❌ Opcao invalida."
if /i "%~1"=="exec_local" set "MSG=Inicializando Teldrive localmente"
if /i "%~1"=="tip_local_1" set "MSG=💡 DICA:"
if /i "%~1"=="tip_local_2" set "MSG=   Teste no navegador: http://localhost:%PORTA%"
if /i "%~1"=="starting_app" set "MSG=🚀 Iniciando aplicacao"
if /i "%~1"=="process_finished" set "MSG=💡 O processo foi encerrado."
if /i "%~1"=="exec_ngrok" set "MSG=Preparando execucao com Ngrok"
if /i "%~1"=="tip_ngrok_1" set "MSG=💡 DICA: O Ngrok eh ideal para testes rapidos."
if /i "%~1"=="tip_ngrok_2" set "MSG=   A URL publica pode mudar no plano gratuito."
if /i "%~1"=="ngrok_not_found" set "MSG=🟡 Ngrok nao encontrado"
if /i "%~1"=="ngrok_downloading" set "MSG=⬇️ Baixando pacote do Ngrok"
if /i "%~1"=="ngrok_extracting" set "MSG=📦 Extraindo arquivos do Ngrok"
if /i "%~1"=="ngrok_ready" set "MSG=✅ Ngrok preparado com sucesso"
if /i "%~1"=="ngrok_already_ready" set "MSG=✅ Ngrok ja esta disponivel"
if /i "%~1"=="ngrok_other_window" set "MSG=🌍 Abra outra janela e execute:"
if /i "%~1"=="exec_cloudflare" set "MSG=Preparando execucao com Cloudflare Tunnel"
if /i "%~1"=="tip_cf_1" set "MSG=💡 DICA: Cloudflare Tunnel eh melhor para uso com dominio proprio."
if /i "%~1"=="tip_cf_2" set "MSG=   Exemplo: https://drive.seudominio.com"
if /i "%~1"=="cf_not_found" set "MSG=🟡 Cloudflared nao encontrado"
if /i "%~1"=="cf_downloading" set "MSG=⬇️ Baixando executavel do Cloudflared"
if /i "%~1"=="cf_ready" set "MSG=✅ Cloudflared preparado com sucesso"
if /i "%~1"=="cf_already_ready" set "MSG=✅ Cloudflared ja esta disponivel"
if /i "%~1"=="cf_other_window" set "MSG=☁️ Abra outra janela e execute:"
if /i "%~1"=="config_removed_recreate" set "MSG=🛠️ Arquivo config.toml removido para nova configuracao"
if /i "%~1"=="exec_headless" set "MSG=Modo headless selecionado"
if /i "%~1"=="tip_headless_1" set "MSG=💡 DICA: Headless e util para manter o Teldrive rodando"
if /i "%~1"=="tip_headless_2" set "MSG=   sem interagir muito com a janela."
if /i "%~1"=="headless_example" set "MSG=🤖 Exemplo de uso assistido"
if /i "%~1"=="headless_starting" set "MSG=Modo headless iniciado"
if /i "%~1"=="headless_started_other_window" set "MSG=✅ Teldrive iniciado em outra janela."
if /i "%~1"=="folder_opened" set "MSG=📂 Pasta do projeto aberta"
if /i "%~1"=="no_log_found" set "MSG=Nenhum arquivo de log foi encontrado."
if /i "%~1"=="update_title" set "MSG=Atualizando projeto e dependencias"
if /i "%~1"=="project_not_cloned" set "MSG=❌ Projeto ainda nao foi clonado"
if /i "%~1"=="repo_update_fail" set "MSG=⚠️ Falha ao atualizar repositorio"
if /i "%~1"=="repo_updated" set "MSG=✅ Repositorio atualizado"
if /i "%~1"=="fatal_error" set "MSG=❌ O instalador encontrou um erro critico."
if /i "%~1"=="check_log_here" set "MSG=📄 Consulte o log em:"
if /i "%~1"=="fatal_log_msg" set "MSG=❌ Encerramento por erro critico"
if /i "%~1"=="ask_open_log_title" set "MSG=💡 Deseja abrir o LOG para ver tudo o que aconteceu?"
if /i "%~1"=="ask_open_log_sub" set "MSG=   downloads, atualizacoes, erros e detalhes tecnicos."
if /i "%~1"=="ask_open_log_choice" set "MSG=📄 Abrir a tela de LOG?"
if /i "%~1"=="log_opened" set "MSG=📄 Arquivo de log aberto"
if /i "%~1"=="required_empty" set "MSG=❌ Este campo e obrigatorio."
if /i "%~1"=="required_log" set "MSG=⚠️ Campo obrigatorio nao preenchido"
if /i "%~1"=="required_ok" set "MSG=✅ Campo preenchido com sucesso"
if /i "%~1"=="download_start" set "MSG=⬇️ Iniciando download de"
if /i "%~1"=="download_fail" set "MSG=❌ Falha no download de"
if /i "%~1"=="download_ok" set "MSG=✅ Download concluido com sucesso:"
if /i "%~1"=="service_title" set "MSG=⚙️ CONFIGURAR MODO DE EXECUCAO"
if /i "%~1"=="service_line1" set "MSG=Rodar como servico significa deixar o Teldrive"
if /i "%~1"=="service_line2" set "MSG=funcionando de forma mais continua e discreta."
if /i "%~1"=="service_adv" set "MSG=✅ Vantagens:"
if /i "%~1"=="service_adv1" set "MSG=   - nao precisa deixar a janela aberta o tempo todo"
if /i "%~1"=="service_adv2" set "MSG=   - melhor para uso continuo"
if /i "%~1"=="service_adv3" set "MSG=   - mais pratico para manter ativo"
if /i "%~1"=="service_warn" set "MSG=⚠️ Pontos de atencao:"
if /i "%~1"=="service_warn1" set "MSG=   - pode precisar de permissoes de administrador"
if /i "%~1"=="service_warn2" set "MSG=   - manutencao e diagnostico ficam um pouco mais tecnicos"
if /i "%~1"=="service_warn3" set "MSG=   - para testes simples, o modo normal eh mais facil"
if /i "%~1"=="service_question" set "MSG=👉 Deseja marcar o Teldrive para uso em modo servico?"
if /i "%~1"=="service_mode_normal_ok" set "MSG=✅ Modo normal configurado."
if /i "%~1"=="service_mode_service_ok" set "MSG=✅ Modo servico preferencial configurado."
if /i "%~1"=="service_mode_log_normal" set "MSG=📝 Usuario escolheu modo normal"
if /i "%~1"=="service_mode_log_service" set "MSG=📝 Usuario escolheu modo servico preferencial"
if /i "%~1"=="shortcut_step" set "MSG=Gerando launcher para atualizar e iniciar o Teldrive"
if /i "%~1"=="shortcut_created_ok" set "MSG=✅ Launcher criado com sucesso."
if /i "%~1"=="shortcut_created_fail" set "MSG=❌ Falha ao criar launcher."
if /i "%~1"=="desktop_step" set "MSG=Criando icone na area de trabalho"
if /i "%~1"=="desktop_ok" set "MSG=✅ Icone criado com sucesso na area de trabalho."
if /i "%~1"=="desktop_fail" set "MSG=❌ Falha ao criar o icone da area de trabalho."
if /i "%~1"=="change_port_title" set "MSG=Alterando a porta do Teldrive"
if /i "%~1"=="change_port_hint" set "MSG=💡 Escolha uma porta entre 1 e 65535. Exemplo: 8081"
if /i "%~1"=="change_port_prompt" set "MSG=Nova porta:"
if /i "%~1"=="invalid_port" set "MSG=❌ Porta invalida. Digite apenas numeros entre 1 e 65535."
if /i "%~1"=="port_changed_ok" set "MSG=✅ Porta alterada com sucesso. O launcher foi atualizado."
if /i "%~1"=="show_port_status_title" set "MSG=Verificando quem esta usando a porta atual"
if /i "%~1"=="port_status_busy" set "MSG=⚠️ A porta atual esta ocupada."
if /i "%~1"=="port_status_free" set "MSG=✅ A porta atual esta livre."
if /i "%~1"=="paths_title" set "MSG=CAMINHOS SALVOS / ESCOLHIDOS"
if /i "%~1"=="crash_detected" set "MSG=❌ Foi detectada uma falha na execucao do Teldrive."
if /i "%~1"=="crash_check_log" set "MSG=📄 Verifique o log para identificar o erro."
if /i "%~1"=="app_finished_ok" set "MSG=✅ Teldrive finalizado sem erro."
if /i "%~1"=="installer_closed_user" set "MSG=👋 Instalador encerrado pelo usuario"
if /i "%~1"=="process_finished_ok" set "MSG=✅ Processo finalizado."
if /i "%~1"=="closed_ok" set "MSG=👋 Encerrado com sucesso."
if not defined MSG set "MSG=%~1"
goto :eof

:msg_en
if /i "%~1"=="welcome_title" set "MSG=🚀 %APP_NAME%"
if /i "%~1"=="welcome_version" set "MSG=🏷️ Version: v%APP_VERSION%"
if /i "%~1"=="welcome_sub1" set "MSG=🛠️ Guided environment setup"
if /i "%~1"=="welcome_sub2" set "MSG=💻 Git + Go + Configuration + Execution"
if /i "%~1"=="welcome_sub3" set "MSG=😊 Ready to make your Teldrive shine!"
if /i "%~1"=="ask_language" set "MSG=What language would you like to use?"
if /i "%~1"=="lang_pt" set "MSG=[1] PT-BR - Portuguese"
if /i "%~1"=="lang_en" set "MSG=[2] EN - English"
if /i "%~1"=="lang_es" set "MSG=[3] ES - Spanish"
if /i "%~1"=="lang_selected" set "MSG=✅ Language selected successfully."
if /i "%~1"=="invalid_language" set "MSG=❌ Invalid language option."
if /i "%~1"=="date_warn_nonlocal" set "MSG=⚠️ Windows is not using dd/mm/yyyy. The log will use the international format."
if /i "%~1"=="step_permissions" set "MSG=Checking system permissions"
if /i "%~1"=="step_internet" set "MSG=Checking internet connection"
if /i "%~1"=="step_running_check" set "MSG=Checking whether another Teldrive is already running"
if /i "%~1"=="step_dependencies" set "MSG=Checking installed dependencies"
if /i "%~1"=="step_repo" set "MSG=Preparing or updating the Teldrive repository"
if /i "%~1"=="step_project_deps" set "MSG=Updating project dependencies"
if /i "%~1"=="step_port" set "MSG=Checking current port"
if /i "%~1"=="step_config" set "MSG=Creating initial configuration"
if /i "%~1"=="not_admin" set "MSG=⚠️ The script is not running as administrator"
if /i "%~1"=="install_may_fail" set "MSG=Some installations may fail"
if /i "%~1"=="continue_anyway" set "MSG=👉 Do you want to continue anyway?"
if /i "%~1"=="cancel_no_admin" set "MSG=⚠️ Execution cancelled due to missing privileges"
if /i "%~1"=="admin_detected" set "MSG=✅ Administrative permissions detected"
if /i "%~1"=="no_internet" set "MSG=❌ No internet connection"
if /i "%~1"=="internet_ok" set "MSG=🌐 Internet connection confirmed"
if /i "%~1"=="connect_internet_retry" set "MSG=❌ Connect to the internet and try again."
if /i "%~1"=="running_found" set "MSG=⚠️ A running Teldrive instance was found"
if /i "%~1"=="running_not_found" set "MSG=✅ No Teldrive instance found"
if /i "%~1"=="running_detected_machine" set "MSG=⚠️ It looks like Teldrive is already running on this machine."
if /i "%~1"=="running_menu_title" set "MSG=Choose what to do with the running instance:"
if /i "%~1"=="running_menu_1" set "MSG=[1] Continue anyway"
if /i "%~1"=="running_menu_2" set "MSG=[2] Stop current Teldrive and continue"
if /i "%~1"=="running_menu_3" set "MSG=[3] Cancel"
if /i "%~1"=="running_kill_ok" set "MSG=✅ Current process stopped successfully"
if /i "%~1"=="running_kill_fail" set "MSG=❌ Could not stop current process"
if /i "%~1"=="running_cancelled" set "MSG=⚠️ Operation cancelled by user"
if /i "%~1"=="detected_teldrive_exe" set "MSG=⚠️ Detected teldrive.exe process running"
if /i "%~1"=="detected_teldrive_process" set "MSG=⚠️ Detected Teldrive related process running"
if /i "%~1"=="detected_port_possible_instance" set "MSG=⚠️ Current port is in use; there may be a Teldrive instance running"
if /i "%~1"=="git_installed" set "MSG=🟢 Git is already installed"
if /i "%~1"=="git_not_found" set "MSG=🟡 Git not found"
if /i "%~1"=="git_downloading" set "MSG=⬇️ Downloading Git installer"
if /i "%~1"=="git_installing" set "MSG=⚙️ Running silent Git installation"
if /i "%~1"=="git_installed_ok" set "MSG=✅ Git installed successfully"
if /i "%~1"=="git_install_fail" set "MSG=❌ Failed to install Git"
if /i "%~1"=="git_found_but_broken" set "MSG=⚠️ Git was found, but its configuration seems broken"
if /i "%~1"=="git_config_invalid" set "MSG=❌ Git configuration file seems invalid. Fix it or reinstall Git."
if /i "%~1"=="go_installed" set "MSG=🟢 Go is already installed"
if /i "%~1"=="go_not_found" set "MSG=🟡 Go not found"
if /i "%~1"=="go_downloading" set "MSG=⬇️ Downloading Go installer"
if /i "%~1"=="go_installing" set "MSG=⚙️ Running silent Go installation"
if /i "%~1"=="go_installed_ok" set "MSG=✅ Go installed successfully"
if /i "%~1"=="go_install_fail" set "MSG=❌ Failed to install Go"
if /i "%~1"=="existing_install_title" set "MSG=A previous Teldrive installation was found."
if /i "%~1"=="existing_install_1" set "MSG=[1] Update this installation"
if /i "%~1"=="existing_install_2" set "MSG=[2] Reinstall keeping configuration"
if /i "%~1"=="existing_install_3" set "MSG=[3] Reinstall from scratch"
if /i "%~1"=="existing_install_4" set "MSG=[4] Cancel"
if /i "%~1"=="project_not_installed" set "MSG=📦 Project is not installed yet"
if /i "%~1"=="cloning_repo" set "MSG=🌍 Cloning official Teldrive repository"
if /i "%~1"=="clone_fail" set "MSG=❌ Failed to clone repository"
if /i "%~1"=="clone_ok" set "MSG=✅ Repository cloned successfully"
if /i "%~1"=="project_already_installed" set "MSG=📁 Project is already installed"
if /i "%~1"=="updating_repo" set "MSG=🔄 Updating local repository"
if /i "%~1"=="repo_update_warn" set "MSG=⚠️ Could not update repository, continuing with local files"
if /i "%~1"=="repo_update_ok" set "MSG=✅ Repository updated successfully"
if /i "%~1"=="reinstall_keep_start" set "MSG=♻️ Reinstalling project while keeping configuration"
if /i "%~1"=="reinstall_clean_start" set "MSG=🧹 Reinstalling project from scratch"
if /i "%~1"=="config_found" set "MSG=✅ config.toml file found"
if /i "%~1"=="external_config_found" set "MSG=📄 A previous configuration was found:"
if /i "%~1"=="reuse_found_config" set "MSG=Do you want to reuse this configuration?"
if /i "%~1"=="ask_db_url" set "MSG=Paste PostgreSQL/Neon database URL:"
if /i "%~1"=="ask_app_id" set "MSG=Enter Telegram App ID:"
if /i "%~1"=="ask_app_hash" set "MSG=Enter Telegram App Hash:"
if /i "%~1"=="ask_jwt_secret" set "MSG=Enter JWT key:"
if /i "%~1"=="ask_redis_optional" set "MSG=Enter Redis URL (optional):"
if /i "%~1"=="ask_bot_yesno" set "MSG=Do you want to configure a Telegram bot? (y/n):"
if /i "%~1"=="ask_bot_token" set "MSG=Enter Telegram bot token:"
if /i "%~1"=="config_created_ok" set "MSG=✅ config.toml file created successfully"
if /i "%~1"=="config_created_fail" set "MSG=❌ Failed to create config.toml file"
if /i "%~1"=="before_mode_define" set "MSG=💡 Before continuing, let's define preferred usage mode."
if /i "%~1"=="create_desktop_icon_now" set "MSG=🖥️ Do you want to create a desktop icon now to update and start Teldrive?"
if /i "%~1"=="shortcut_skip_now" set "MSG=ℹ️ User chose not to create shortcut now"
if /i "%~1"=="menu_title" set "MSG=🚀 MAIN MENU - %APP_NAME% v%APP_VERSION%"
if /i "%~1"=="menu_run_local" set "MSG=[1] ▶️ Run locally"
if /i "%~1"=="menu_run_ngrok" set "MSG=[2] 🌍 Run with Ngrok"
if /i "%~1"=="menu_run_cf" set "MSG=[3] ☁️ Run with Cloudflare Tunnel"
if /i "%~1"=="menu_reconfig" set "MSG=[4] ⚙️ Reconfigure config.toml"
if /i "%~1"=="menu_headless" set "MSG=[5] 🤖 Run in headless mode"
if /i "%~1"=="menu_folder" set "MSG=[6] 📂 Open project folder"
if /i "%~1"=="menu_log" set "MSG=[7] 📜 View log file"
if /i "%~1"=="menu_shortcut" set "MSG=[8] 🖥️ Create/Recreate desktop shortcut"
if /i "%~1"=="menu_update" set "MSG=[9] 🔄 Update project and dependencies"
if /i "%~1"=="menu_mode" set "MSG=[10] ⚙️ Configure execution mode"
if /i "%~1"=="menu_port" set "MSG=[11] 🔌 Change port"
if /i "%~1"=="menu_port_status" set "MSG=[12] 🔍 Check port"
if /i "%~1"=="menu_paths" set "MSG=[13] 📍 Show saved paths"
if /i "%~1"=="menu_exit" set "MSG=[0] 👋 Exit"
if /i "%~1"=="mode_current_service" set "MSG=💡 Current mode: PREFERRED SERVICE"
if /i "%~1"=="mode_current_normal" set "MSG=💡 Current mode: NORMAL"
if /i "%~1"=="current_port" set "MSG=🔌 Current port: %PORTA%"
if /i "%~1"=="menu_choose" set "MSG=👉 Choose an option:"
if /i "%~1"=="invalid_option" set "MSG=⚠️ Invalid option entered"
if /i "%~1"=="invalid_option_print" set "MSG=❌ Invalid option."
if /i "%~1"=="exec_local" set "MSG=Starting Teldrive locally"
if /i "%~1"=="tip_local_1" set "MSG=💡 TIP:"
if /i "%~1"=="tip_local_2" set "MSG=   Test in browser: http://localhost:%PORTA%"
if /i "%~1"=="starting_app" set "MSG=🚀 Starting application"
if /i "%~1"=="process_finished" set "MSG=💡 The process has ended."
if /i "%~1"=="exec_ngrok" set "MSG=Preparing execution with Ngrok"
if /i "%~1"=="tip_ngrok_1" set "MSG=💡 TIP: Ngrok is ideal for quick tests."
if /i "%~1"=="tip_ngrok_2" set "MSG=   Public URL may change on free plan."
if /i "%~1"=="ngrok_not_found" set "MSG=🟡 Ngrok not found"
if /i "%~1"=="ngrok_downloading" set "MSG=⬇️ Downloading Ngrok package"
if /i "%~1"=="ngrok_extracting" set "MSG=📦 Extracting Ngrok files"
if /i "%~1"=="ngrok_ready" set "MSG=✅ Ngrok prepared successfully"
if /i "%~1"=="ngrok_already_ready" set "MSG=✅ Ngrok already available"
if /i "%~1"=="ngrok_other_window" set "MSG=🌍 Open another window and run:"
if /i "%~1"=="exec_cloudflare" set "MSG=Preparing execution with Cloudflare Tunnel"
if /i "%~1"=="tip_cf_1" set "MSG=💡 TIP: Cloudflare Tunnel is better for your own domain."
if /i "%~1"=="tip_cf_2" set "MSG=   Example: https://drive.yourdomain.com"
if /i "%~1"=="cf_not_found" set "MSG=🟡 Cloudflared not found"
if /i "%~1"=="cf_downloading" set "MSG=⬇️ Downloading Cloudflared executable"
if /i "%~1"=="cf_ready" set "MSG=✅ Cloudflared prepared successfully"
if /i "%~1"=="cf_already_ready" set "MSG=✅ Cloudflared already available"
if /i "%~1"=="cf_other_window" set "MSG=☁️ Open another window and run:"
if /i "%~1"=="config_removed_recreate" set "MSG=🛠️ config.toml removed for reconfiguration"
if /i "%~1"=="exec_headless" set "MSG=Headless mode selected"
if /i "%~1"=="tip_headless_1" set "MSG=💡 TIP: Headless is useful to keep Teldrive running"
if /i "%~1"=="tip_headless_2" set "MSG=   without interacting much with the window."
if /i "%~1"=="headless_example" set "MSG=🤖 Guided example"
if /i "%~1"=="headless_starting" set "MSG=Headless mode started"
if /i "%~1"=="headless_started_other_window" set "MSG=✅ Teldrive started in another window."
if /i "%~1"=="folder_opened" set "MSG=📂 Project folder opened"
if /i "%~1"=="no_log_found" set "MSG=No log file was found."
if /i "%~1"=="update_title" set "MSG=Updating project and dependencies"
if /i "%~1"=="project_not_cloned" set "MSG=❌ Project has not been cloned yet"
if /i "%~1"=="repo_update_fail" set "MSG=⚠️ Failed to update repository"
if /i "%~1"=="repo_updated" set "MSG=✅ Repository updated"
if /i "%~1"=="fatal_error" set "MSG=❌ Installer encountered a critical error."
if /i "%~1"=="check_log_here" set "MSG=📄 Check the log at:"
if /i "%~1"=="fatal_log_msg" set "MSG=❌ Closed due to critical error"
if /i "%~1"=="ask_open_log_title" set "MSG=💡 Do you want to open the LOG to review everything?"
if /i "%~1"=="ask_open_log_sub" set "MSG=   downloads, updates, errors and technical details."
if /i "%~1"=="ask_open_log_choice" set "MSG=📄 Open the LOG screen?"
if /i "%~1"=="log_opened" set "MSG=📄 Log file opened"
if /i "%~1"=="required_empty" set "MSG=❌ This field is required."
if /i "%~1"=="required_log" set "MSG=⚠️ Required field was left empty"
if /i "%~1"=="required_ok" set "MSG=✅ Field filled successfully"
if /i "%~1"=="download_start" set "MSG=⬇️ Starting download of"
if /i "%~1"=="download_fail" set "MSG=❌ Failed to download"
if /i "%~1"=="download_ok" set "MSG=✅ Download completed successfully:"
if /i "%~1"=="service_title" set "MSG=⚙️ CONFIGURE EXECUTION MODE"
if /i "%~1"=="service_line1" set "MSG=Running as a service means keeping Teldrive"
if /i "%~1"=="service_line2" set "MSG=running more continuously and discreetly."
if /i "%~1"=="service_adv" set "MSG=✅ Advantages:"
if /i "%~1"=="service_adv1" set "MSG=   - no need to keep the window open all the time"
if /i "%~1"=="service_adv2" set "MSG=   - better for continuous usage"
if /i "%~1"=="service_adv3" set "MSG=   - easier to keep active"
if /i "%~1"=="service_warn" set "MSG=⚠️ Attention points:"
if /i "%~1"=="service_warn1" set "MSG=   - may require administrator privileges"
if /i "%~1"=="service_warn2" set "MSG=   - maintenance and diagnostics are more technical"
if /i "%~1"=="service_warn3" set "MSG=   - for simple tests, normal mode is easier"
if /i "%~1"=="service_question" set "MSG=👉 Do you want to mark Teldrive for service mode?"
if /i "%~1"=="service_mode_normal_ok" set "MSG=✅ Normal mode configured."
if /i "%~1"=="service_mode_service_ok" set "MSG=✅ Preferred service mode configured."
if /i "%~1"=="service_mode_log_normal" set "MSG=📝 User chose normal mode"
if /i "%~1"=="service_mode_log_service" set "MSG=📝 User chose preferred service mode"
if /i "%~1"=="shortcut_step" set "MSG=Generating launcher to update and start Teldrive"
if /i "%~1"=="shortcut_created_ok" set "MSG=✅ Launcher created successfully."
if /i "%~1"=="shortcut_created_fail" set "MSG=❌ Failed to create launcher."
if /i "%~1"=="desktop_step" set "MSG=Creating desktop icon"
if /i "%~1"=="desktop_ok" set "MSG=✅ Desktop icon created successfully."
if /i "%~1"=="desktop_fail" set "MSG=❌ Failed to create desktop icon."
if /i "%~1"=="change_port_title" set "MSG=Changing Teldrive port"
if /i "%~1"=="change_port_hint" set "MSG=💡 Choose a port between 1 and 65535. Example: 8081"
if /i "%~1"=="change_port_prompt" set "MSG=New port:"
if /i "%~1"=="invalid_port" set "MSG=❌ Invalid port. Enter only numbers between 1 and 65535."
if /i "%~1"=="port_changed_ok" set "MSG=✅ Port changed successfully. Launcher updated."
if /i "%~1"=="show_port_status_title" set "MSG=Checking who is using the current port"
if /i "%~1"=="port_status_busy" set "MSG=⚠️ Current port is busy."
if /i "%~1"=="port_status_free" set "MSG=✅ Current port is free."
if /i "%~1"=="paths_title" set "MSG=SAVED / CHOSEN PATHS"
if /i "%~1"=="crash_detected" set "MSG=❌ A failure during Teldrive execution was detected."
if /i "%~1"=="crash_check_log" set "MSG=📄 Check the log to identify the error."
if /i "%~1"=="app_finished_ok" set "MSG=✅ Teldrive finished without errors."
if /i "%~1"=="installer_closed_user" set "MSG=👋 Installer closed by user"
if /i "%~1"=="process_finished_ok" set "MSG=✅ Process finished."
if /i "%~1"=="closed_ok" set "MSG=👋 Closed successfully."
if not defined MSG set "MSG=%~1"
goto :eof

:msg_es
if /i "%~1"=="welcome_title" set "MSG=🚀 %APP_NAME%"
if /i "%~1"=="welcome_version" set "MSG=🏷️ Version: v%APP_VERSION%"
if /i "%~1"=="welcome_sub1" set "MSG=🛠️ Instalacion guiada del entorno"
if /i "%~1"=="welcome_sub2" set "MSG=💻 Git + Go + Configuracion + Ejecucion"
if /i "%~1"=="welcome_sub3" set "MSG=😊 Listo para dejar tu Teldrive impecable!"
if /i "%~1"=="ask_language" set "MSG=Que idioma desea usar?"
if /i "%~1"=="lang_pt" set "MSG=[1] PT-BR - Portugues"
if /i "%~1"=="lang_en" set "MSG=[2] EN - English"
if /i "%~1"=="lang_es" set "MSG=[3] ES - Espanol"
if /i "%~1"=="lang_selected" set "MSG=✅ Idioma seleccionado con exito."
if /i "%~1"=="invalid_language" set "MSG=❌ Opcion invalida de idioma."
if /i "%~1"=="date_warn_nonlocal" set "MSG=⚠️ Windows no esta en formato dd/mm/yyyy. El log usara el formato internacional."
if /i "%~1"=="step_permissions" set "MSG=Verificando permisos del sistema"
if /i "%~1"=="step_internet" set "MSG=Verificando conexion a internet"
if /i "%~1"=="step_running_check" set "MSG=Verificando si ya existe otro Teldrive en ejecucion"
if /i "%~1"=="step_dependencies" set "MSG=Verificando dependencias instaladas"
if /i "%~1"=="step_repo" set "MSG=Preparando o actualizando el repositorio de Teldrive"
if /i "%~1"=="step_project_deps" set "MSG=Actualizando dependencias del proyecto"
if /i "%~1"=="step_port" set "MSG=Verificando el puerto actual"
if /i "%~1"=="step_config" set "MSG=Creando configuracion inicial"
if /i "%~1"=="not_admin" set "MSG=⚠️ El script no se esta ejecutando como administrador"
if /i "%~1"=="install_may_fail" set "MSG=Algunas instalaciones pueden fallar"
if /i "%~1"=="continue_anyway" set "MSG=👉 Desea continuar de todos modos?"
if /i "%~1"=="cancel_no_admin" set "MSG=⚠️ Ejecucion cancelada por falta de privilegios"
if /i "%~1"=="admin_detected" set "MSG=✅ Permisos administrativos detectados"
if /i "%~1"=="no_internet" set "MSG=❌ Sin conexion a internet"
if /i "%~1"=="internet_ok" set "MSG=🌐 Conexion a internet confirmada"
if /i "%~1"=="connect_internet_retry" set "MSG=❌ Conectese a internet e intentelo nuevamente."
if /i "%~1"=="running_found" set "MSG=⚠️ Se encontro una instancia de Teldrive en ejecucion"
if /i "%~1"=="running_not_found" set "MSG=✅ No se encontro ninguna instancia de Teldrive"
if /i "%~1"=="running_detected_machine" set "MSG=⚠️ Parece que Teldrive ya esta funcionando en esta maquina."
if /i "%~1"=="running_menu_title" set "MSG=Elija que hacer con la instancia en ejecucion:"
if /i "%~1"=="running_menu_1" set "MSG=[1] Continuar de todos modos"
if /i "%~1"=="running_menu_2" set "MSG=[2] Cerrar el Teldrive actual y continuar"
if /i "%~1"=="running_menu_3" set "MSG=[3] Cancelar"
if /i "%~1"=="running_kill_ok" set "MSG=✅ Proceso actual cerrado con exito"
if /i "%~1"=="running_kill_fail" set "MSG=❌ No fue posible cerrar el proceso actual"
if /i "%~1"=="running_cancelled" set "MSG=⚠️ Operacion cancelada por el usuario"
if /i "%~1"=="detected_teldrive_exe" set "MSG=⚠️ Se detecto el proceso teldrive.exe en ejecucion"
if /i "%~1"=="detected_teldrive_process" set "MSG=⚠️ Se detecto un proceso relacionado con Teldrive en ejecucion"
if /i "%~1"=="detected_port_possible_instance" set "MSG=⚠️ El puerto actual esta en uso; puede haber una instancia de Teldrive ejecutandose"
if /i "%~1"=="git_installed" set "MSG=🟢 Git ya esta instalado"
if /i "%~1"=="git_not_found" set "MSG=🟡 Git no encontrado"
if /i "%~1"=="git_downloading" set "MSG=⬇️ Descargando instalador de Git"
if /i "%~1"=="git_installing" set "MSG=⚙️ Ejecutando instalacion silenciosa de Git"
if /i "%~1"=="git_installed_ok" set "MSG=✅ Git instalado con exito"
if /i "%~1"=="git_install_fail" set "MSG=❌ Error al instalar Git"
if /i "%~1"=="git_found_but_broken" set "MSG=⚠️ Git fue encontrado, pero su configuracion parece danada"
if /i "%~1"=="git_config_invalid" set "MSG=❌ El archivo de configuracion de Git parece invalido."
if /i "%~1"=="go_installed" set "MSG=🟢 Go ya esta instalado"
if /i "%~1"=="go_not_found" set "MSG=🟡 Go no encontrado"
if /i "%~1"=="go_downloading" set "MSG=⬇️ Descargando instalador de Go"
if /i "%~1"=="go_installing" set "MSG=⚙️ Ejecutando instalacion silenciosa de Go"
if /i "%~1"=="go_installed_ok" set "MSG=✅ Go instalado con exito"
if /i "%~1"=="go_install_fail" set "MSG=❌ Error al instalar Go"
if /i "%~1"=="existing_install_title" set "MSG=Se encontro una instalacion anterior de Teldrive."
if /i "%~1"=="existing_install_1" set "MSG=[1] Actualizar esta instalacion"
if /i "%~1"=="existing_install_2" set "MSG=[2] Reinstalar manteniendo configuracion"
if /i "%~1"=="existing_install_3" set "MSG=[3] Reinstalar desde cero"
if /i "%~1"=="existing_install_4" set "MSG=[4] Cancelar"
if /i "%~1"=="project_not_installed" set "MSG=📦 El proyecto aun no esta instalado"
if /i "%~1"=="cloning_repo" set "MSG=🌍 Clonando el repositorio oficial de Teldrive"
if /i "%~1"=="clone_fail" set "MSG=❌ Error al clonar el repositorio"
if /i "%~1"=="clone_ok" set "MSG=✅ Repositorio clonado con exito"
if /i "%~1"=="project_already_installed" set "MSG=📁 El proyecto ya esta instalado"
if /i "%~1"=="updating_repo" set "MSG=🔄 Actualizando repositorio local"
if /i "%~1"=="repo_update_warn" set "MSG=⚠️ No fue posible actualizar el repositorio"
if /i "%~1"=="repo_update_ok" set "MSG=✅ Repositorio actualizado con exito"
if /i "%~1"=="reinstall_keep_start" set "MSG=♻️ Reinstalando el proyecto manteniendo configuracion"
if /i "%~1"=="reinstall_clean_start" set "MSG=🧹 Reinstalando el proyecto desde cero"
if /i "%~1"=="config_found" set "MSG=✅ Archivo config.toml encontrado"
if /i "%~1"=="external_config_found" set "MSG=📄 Se encontro una configuracion anterior:"
if /i "%~1"=="reuse_found_config" set "MSG=Desea reutilizar esta configuracion?"
if /i "%~1"=="ask_db_url" set "MSG=Pegue la URL de PostgreSQL/Neon:"
if /i "%~1"=="ask_app_id" set "MSG=Ingrese el App ID de Telegram:"
if /i "%~1"=="ask_app_hash" set "MSG=Ingrese el App Hash de Telegram:"
if /i "%~1"=="ask_jwt_secret" set "MSG=Ingrese la clave JWT:"
if /i "%~1"=="ask_redis_optional" set "MSG=Ingrese la URL de Redis (opcional):"
if /i "%~1"=="ask_bot_yesno" set "MSG=Desea configurar un bot de Telegram? (s/n):"
if /i "%~1"=="ask_bot_token" set "MSG=Ingrese el token del bot de Telegram:"
if /i "%~1"=="config_created_ok" set "MSG=✅ Archivo config.toml creado con exito"
if /i "%~1"=="config_created_fail" set "MSG=❌ Error al crear el archivo config.toml"
if /i "%~1"=="before_mode_define" set "MSG=💡 Antes de continuar, vamos a definir el modo de uso preferido."
if /i "%~1"=="create_desktop_icon_now" set "MSG=🖥️ Desea crear ahora un icono en el escritorio para actualizar e iniciar Teldrive?"
if /i "%~1"=="shortcut_skip_now" set "MSG=ℹ️ El usuario eligio no crear el acceso directo ahora"
if /i "%~1"=="menu_title" set "MSG=🚀 MENU PRINCIPAL - %APP_NAME% v%APP_VERSION%"
if /i "%~1"=="menu_run_local" set "MSG=[1] ▶️ Ejecutar localmente"
if /i "%~1"=="menu_run_ngrok" set "MSG=[2] 🌍 Ejecutar con Ngrok"
if /i "%~1"=="menu_run_cf" set "MSG=[3] ☁️ Ejecutar con Cloudflare Tunnel"
if /i "%~1"=="menu_reconfig" set "MSG=[4] ⚙️ Reconfigurar config.toml"
if /i "%~1"=="menu_headless" set "MSG=[5] 🤖 Ejecutar en modo headless"
if /i "%~1"=="menu_folder" set "MSG=[6] 📂 Abrir carpeta del proyecto"
if /i "%~1"=="menu_log" set "MSG=[7] 📜 Ver archivo de log"
if /i "%~1"=="menu_shortcut" set "MSG=[8] 🖥️ Crear/Recrear acceso directo"
if /i "%~1"=="menu_update" set "MSG=[9] 🔄 Actualizar proyecto y dependencias"
if /i "%~1"=="menu_mode" set "MSG=[10] ⚙️ Configurar modo de ejecucion"
if /i "%~1"=="menu_port" set "MSG=[11] 🔌 Cambiar puerto"
if /i "%~1"=="menu_port_status" set "MSG=[12] 🔍 Verificar puerto"
if /i "%~1"=="menu_paths" set "MSG=[13] 📍 Mostrar rutas guardadas"
if /i "%~1"=="menu_exit" set "MSG=[0] 👋 Salir"
if /i "%~1"=="mode_current_service" set "MSG=💡 Modo actual: SERVICIO PREFERENCIAL"
if /i "%~1"=="mode_current_normal" set "MSG=💡 Modo actual: NORMAL"
if /i "%~1"=="current_port" set "MSG=🔌 Puerto actual: %PORTA%"
if /i "%~1"=="menu_choose" set "MSG=👉 Elija una opcion:"
if /i "%~1"=="invalid_option" set "MSG=⚠️ Opcion invalida informada"
if /i "%~1"=="invalid_option_print" set "MSG=❌ Opcion invalida."
if /i "%~1"=="exec_local" set "MSG=Iniciando Teldrive localmente"
if /i "%~1"=="tip_local_1" set "MSG=💡 CONSEJO:"
if /i "%~1"=="tip_local_2" set "MSG=   Pruebe en el navegador: http://localhost:%PORTA%"
if /i "%~1"=="starting_app" set "MSG=🚀 Iniciando aplicacion"
if /i "%~1"=="process_finished" set "MSG=💡 El proceso ha finalizado."
if /i "%~1"=="exec_ngrok" set "MSG=Preparando ejecucion con Ngrok"
if /i "%~1"=="tip_ngrok_1" set "MSG=💡 CONSEJO: Ngrok es ideal para pruebas rapidas."
if /i "%~1"=="tip_ngrok_2" set "MSG=   La URL publica puede cambiar en el plan gratuito."
if /i "%~1"=="ngrok_not_found" set "MSG=🟡 Ngrok no encontrado"
if /i "%~1"=="ngrok_downloading" set "MSG=⬇️ Descargando paquete de Ngrok"
if /i "%~1"=="ngrok_extracting" set "MSG=📦 Extrayendo archivos de Ngrok"
if /i "%~1"=="ngrok_ready" set "MSG=✅ Ngrok preparado con exito"
if /i "%~1"=="ngrok_already_ready" set "MSG=✅ Ngrok ya esta disponible"
if /i "%~1"=="ngrok_other_window" set "MSG=🌍 Abra otra ventana y ejecute:"
if /i "%~1"=="exec_cloudflare" set "MSG=Preparando ejecucion con Cloudflare Tunnel"
if /i "%~1"=="tip_cf_1" set "MSG=💡 CONSEJO: Cloudflare Tunnel es mejor para dominio propio."
if /i "%~1"=="tip_cf_2" set "MSG=   Ejemplo: https://drive.sudominio.com"
if /i "%~1"=="cf_not_found" set "MSG=🟡 Cloudflared no encontrado"
if /i "%~1"=="cf_downloading" set "MSG=⬇️ Descargando ejecutable de Cloudflared"
if /i "%~1"=="cf_ready" set "MSG=✅ Cloudflared preparado con exito"
if /i "%~1"=="cf_already_ready" set "MSG=✅ Cloudflared ya esta disponible"
if /i "%~1"=="cf_other_window" set "MSG=☁️ Abra otra ventana y ejecute:"
if /i "%~1"=="config_removed_recreate" set "MSG=🛠️ Archivo config.toml eliminado para nueva configuracion"
if /i "%~1"=="exec_headless" set "MSG=Modo headless seleccionado"
if /i "%~1"=="tip_headless_1" set "MSG=💡 CONSEJO: Headless es util para mantener Teldrive ejecutandose"
if /i "%~1"=="tip_headless_2" set "MSG=   sin interactuar mucho con la ventana."
if /i "%~1"=="headless_example" set "MSG=🤖 Ejemplo guiado"
if /i "%~1"=="headless_starting" set "MSG=Modo headless iniciado"
if /i "%~1"=="headless_started_other_window" set "MSG=✅ Teldrive iniciado en otra ventana."
if /i "%~1"=="folder_opened" set "MSG=📂 Carpeta del proyecto abierta"
if /i "%~1"=="no_log_found" set "MSG=No se encontro ningun archivo de log."
if /i "%~1"=="update_title" set "MSG=Actualizando proyecto y dependencias"
if /i "%~1"=="project_not_cloned" set "MSG=❌ El proyecto aun no ha sido clonado"
if /i "%~1"=="repo_update_fail" set "MSG=⚠️ Error al actualizar el repositorio"
if /i "%~1"=="repo_updated" set "MSG=✅ Repositorio actualizado"
if /i "%~1"=="fatal_error" set "MSG=❌ El instalador encontro un error critico."
if /i "%~1"=="check_log_here" set "MSG=📄 Consulte el log en:"
if /i "%~1"=="fatal_log_msg" set "MSG=❌ Cierre por error critico"
if /i "%~1"=="ask_open_log_title" set "MSG=💡 Desea abrir el LOG para revisar todo?"
if /i "%~1"=="ask_open_log_sub" set "MSG=   descargas, actualizaciones, errores y detalles tecnicos."
if /i "%~1"=="ask_open_log_choice" set "MSG=📄 Abrir la pantalla de LOG?"
if /i "%~1"=="log_opened" set "MSG=📄 Archivo de log abierto"
if /i "%~1"=="required_empty" set "MSG=❌ Este campo es obligatorio."
if /i "%~1"=="required_log" set "MSG=⚠️ Campo obligatorio no completado"
if /i "%~1"=="required_ok" set "MSG=✅ Campo completado con exito"
if /i "%~1"=="download_start" set "MSG=⬇️ Iniciando descarga de"
if /i "%~1"=="download_fail" set "MSG=❌ Error en la descarga de"
if /i "%~1"=="download_ok" set "MSG=✅ Descarga completada con exito:"
if /i "%~1"=="service_title" set "MSG=⚙️ CONFIGURAR MODO DE EJECUCION"
if /i "%~1"=="service_line1" set "MSG=Ejecutar como servicio significa dejar Teldrive"
if /i "%~1"=="service_line2" set "MSG=funcionando de forma mas continua y discreta."
if /i "%~1"=="service_adv" set "MSG=✅ Ventajas:"
if /i "%~1"=="service_adv1" set "MSG=   - no necesita dejar la ventana abierta todo el tiempo"
if /i "%~1"=="service_adv2" set "MSG=   - mejor para uso continuo"
if /i "%~1"=="service_adv3" set "MSG=   - mas facil de mantener activo"
if /i "%~1"=="service_warn" set "MSG=⚠️ Puntos de atencion:"
if /i "%~1"=="service_warn1" set "MSG=   - puede requerir permisos de administrador"
if /i "%~1"=="service_warn2" set "MSG=   - el mantenimiento y diagnostico son un poco mas tecnicos"
if /i "%~1"=="service_warn3" set "MSG=   - para pruebas simples, el modo normal es mas facil"
if /i "%~1"=="service_question" set "MSG=👉 Desea marcar Teldrive para modo servicio?"
if /i "%~1"=="service_mode_normal_ok" set "MSG=✅ Modo normal configurado."
if /i "%~1"=="service_mode_service_ok" set "MSG=✅ Modo servicio preferencial configurado."
if /i "%~1"=="service_mode_log_normal" set "MSG=📝 El usuario eligio modo normal"
if /i "%~1"=="service_mode_log_service" set "MSG=📝 El usuario eligio modo servicio preferencial"
if /i "%~1"=="shortcut_step" set "MSG=Generando launcher para actualizar e iniciar Teldrive"
if /i "%~1"=="shortcut_created_ok" set "MSG=✅ Launcher creado con exito."
if /i "%~1"=="shortcut_created_fail" set "MSG=❌ Error al crear launcher."
if /i "%~1"=="desktop_step" set "MSG=Creando icono en el escritorio"
if /i "%~1"=="desktop_ok" set "MSG=✅ Icono creado con exito."
if /i "%~1"=="desktop_fail" set "MSG=❌ Error al crear el icono."
if /i "%~1"=="change_port_title" set "MSG=Cambiando el puerto de Teldrive"
if /i "%~1"=="change_port_hint" set "MSG=💡 Elija un puerto entre 1 y 65535. Ejemplo: 8081"
if /i "%~1"=="change_port_prompt" set "MSG=Nuevo puerto:"
if /i "%~1"=="invalid_port" set "MSG=❌ Puerto invalido. Ingrese solo numeros entre 1 y 65535."
if /i "%~1"=="port_changed_ok" set "MSG=✅ Puerto cambiado con exito. Launcher actualizado."
if /i "%~1"=="show_port_status_title" set "MSG=Verificando quien usa el puerto actual"
if /i "%~1"=="port_status_busy" set "MSG=⚠️ El puerto actual esta ocupado."
if /i "%~1"=="port_status_free" set "MSG=✅ El puerto actual esta libre."
if /i "%~1"=="paths_title" set "MSG=RUTAS GUARDADAS / ELEGIDAS"
if /i "%~1"=="crash_detected" set "MSG=❌ Se detecto una falla en la ejecucion de Teldrive."
if /i "%~1"=="crash_check_log" set "MSG=📄 Revise el log para identificar el error."
if /i "%~1"=="app_finished_ok" set "MSG=✅ Teldrive finalizo sin errores."
if /i "%~1"=="installer_closed_user" set "MSG=👋 Instalador cerrado por el usuario"
if /i "%~1"=="process_finished_ok" set "MSG=✅ Proceso finalizado."
if /i "%~1"=="closed_ok" set "MSG=👋 Cerrado con exito."
if not defined MSG set "MSG=%~1"
goto :eof