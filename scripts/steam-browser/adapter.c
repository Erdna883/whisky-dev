/* Whisky Dev CEF compatibility adapter. GPL-3.0-or-later.
 * Preserve Valve's browser executable and forward its arguments while forcing
 * the selected browser mode. Steam itself must remain unmodified.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR unused, int show) {
    (void)instance; (void)previous; (void)unused; (void)show;
    wchar_t real[32768];
    DWORD length = GetModuleFileNameW(NULL, real, 32768);
    if (length == 0 || length >= 32768) return 120;
    wchar_t *separator = wcsrchr(real, L'\\');
    if (!separator) return 121;
    const wchar_t *filename = L"steamwebhelper_valve.exe";
    if ((size_t)(separator - real) + 1 + wcslen(filename) >= 32768) return 122;
    wcscpy(separator + 1, filename);

    const wchar_t *arguments = GetCommandLineW();
    if (*arguments == L'"') {
        ++arguments;
        while (*arguments && *arguments != L'"') ++arguments;
        if (*arguments) ++arguments;
    } else {
        while (*arguments && *arguments != L' ' && *arguments != L'\t') ++arguments;
    }
    wchar_t mode[32] = {0};
    DWORD mode_length = GetEnvironmentVariableW(L"WHISKY_STEAM_BROWSER_MODE", mode, 32);
    BOOL responsive = mode_length > 0 && mode_length < 32 && wcscmp(mode, L"responsive") == 0;
    const wchar_t *flags = responsive
        ? L" --disable-gpu --in-process-gpu"
        : L" --disable-gpu --single-process";
    size_t capacity = wcslen(real) + wcslen(arguments) + wcslen(flags) + 4;
    if (capacity > 32768) return 123;
    wchar_t *command = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, capacity * sizeof(wchar_t));
    if (!command) return 124;
    wcscpy(command, L"\""); wcscat(command, real); wcscat(command, L"\"");
    wcscat(command, arguments); wcscat(command, flags);

    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    startup.cb = sizeof(startup);
    BOOL started = CreateProcessW(real, command, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &process);
    HeapFree(GetProcessHeap(), 0, command);
    if (!started) return (int)GetLastError();
    CloseHandle(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD status = 1;
    GetExitCodeProcess(process.hProcess, &status);
    CloseHandle(process.hProcess);
    return (int)status;
}
