@echo off
chcp 65001 >nul
cd /d "%~dp0"
set LOG=%~dp0run_log.txt
> "%LOG%" echo ==== START %DATE% %TIME% ====
call flutter pub get >> "%LOG%" 2>&1
call flutter analyze >> "%LOG%" 2>&1
call flutter test test/parser_test.dart test/export_test.dart test/widget_test.dart >> "%LOG%" 2>&1
call flutter build windows --debug >> "%LOG%" 2>&1
>> "%LOG%" echo ==== BUILD DONE ====
start "" "%~dp0build\windows\x64\runner\Debug\srs_generator.exe"
>> "%LOG%" echo ==== LAUNCHED ====
