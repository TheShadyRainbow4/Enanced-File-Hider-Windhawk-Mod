// ==WindhawkMod==
// @id              enhanced-file-hider
// @name            Enhanced-File-Hider(Fork of Hide Dot Files)
// @description     Hide dotfiles and folders, manage always hide / show / supports multiple types starting with . in Windows Explorer and Desktop
// @version         1.0.9.4
// @author          @TheShadyRainbow4
// @github          https://github.com/TheShaydyRainbow4
// @include         explorer.exe
// @compilerOptions -lcomctl32 -lole32 -loleaut32 -lshell32 -lshlwapi -luuid
// ==/WindhawkMod==

// ==WindhawkModReadme==
/*
# **Introduction**

### This mod hides files and folders starting with a dot (.) in Windows Explorer and Desktop, similar to Unix/Linux systems. It also allows you more fine grained control over files that can be set to always hidden / always shown
&nbsp;
&nbsp;
![Screenshot](https://i.imgur.com/PsdAL9U.png)
&nbsp;
&nbsp;
![Screenshot](https://i.imgur.com/tFnPZME.png)  
&nbsp;                                  
&nbsp; 
&nbsp;
## How It Works
This mod **filters files directly from directory listings** at the system level.
It does **not** modify file attributes (like the "hidden" attribute) and **does not** depend on Windows Explorer's "Show hidden files" setting.
Files are completely hidden from view regardless of Explorer's hidden file visibility settings.

## Key Benefits
- **Independent of Explorer settings**: Works regardless of whether "Show hidden files" is enabled or disabled
- **No file attribute modification**: Files remain unchanged on disk
- **System-wide filtering**: Affects all Explorer views and file dialogs
- **Still Functional Within Command Line**: Files are still visible to the terminal and other command line utilities

## Configuration
You can exclude specific files from being hidden using the dotfile whitelist, or specify 
additional files to always hide regardless of whether they start with a dot. Enable & Disable a Folder/Desktop Context menu item to more easily toggle the mods hiding function. You can also set a keyboard hot-key combo to toggle the mods hiding as well

## Display Modes
Choose how dotfiles should be handled:
- **Never show**: Files are completely hidden from directory listings (default)
- **Show as hidden**: Files are shown with the hidden attribute (like Unix `ls -a`)
- **Show as system**: Files are shown with both hidden and system attributes

## Filename Matching
- **Case-insensitive**: Filenames are matched regardless of case (e.g., `.Gitignore` will match `.gitignore`)
- **Pattern matching**: Supports wildcards using Windows pattern matching syntax
  - `*` matches zero or more characters
  - `?` matches exactly one character
  - Examples: `.env*` matches `.env`, `.env.local`, `.env.production`

## Settings

#### - **Display Mode**: How to handle dotfiles 
+ (Never Show [Very hidden], Show as hidden [Hidden File Attribute], Show as System & Hidden [Hidden & System Attribute] ) &nbsp;
&nbsp;
&nbsp;
&nbsp;
#### - **Dotfile Whitelist**: List of dotfile patterns to show 
+ (e.g., `.gitignore`, `.env*`, `.*.config`)
&nbsp;
&nbsp;
&nbsp;
#### - **Always Hide**: List of filename patterns to always hide, even if they don't start with a dot
+ (e.g., `desktop.ini`, `Thumbs.db`, `*.tmp`)
&nbsp;
&nbsp;
&nbsp;
#### - **Context Menu**: Toggle the desktop / Folder Context menu to quickly toggle the mod on and off 
+ (Context menu item `Define Custom Display Text` / `Disable Menu Entry Entirely`)
&nbsp;
&nbsp;
&nbsp;
#### - **Hot Key**: Assign a Hot-Key combination to toggle the mod on / off     (e.g., `Ctrl` + `Shift`, `H`)
&nbsp;
&nbsp;
&nbsp;
![Screenshot](https://i.imgur.com/GlluYRi.png)
## Examples:
- To show `.gitignore`: add `.gitignore` to dotfile whitelist
- To show all `.env*` files: add `.env*` to dotfile whitelist
- To hide `desktop.ini`: add `desktop.ini` to always-hide list
- To hide all `.tmp` files: add `*.tmp` to always-hide list
- `.env.local` will be shown if `.env*` is whitelisted
&nbsp;
&nbsp;
&nbsp;
### - **Whitelist/Always Hide** 
  * `SecretFile.txt` = Hides all files of that same name \
  * `*.txt` = Hides all Text files  
  * `C:\Users\YourName\Documents\SecretFile.txt\` = BAD! This Will not work you silly goose!
  * The mods logic does not allow for it to handle an entire path as it works via pattern matching. You can only specify files and folder names.

&nbsp;
## Important Notes
###  - **No file attributes are modified** 
-    hidden files retain their original attributes
&nbsp;
###  - **Independent of Explorer settings** 
-    works regardless of "Show hidden files" setting
&nbsp;
###  - **Other applications** 
-    can still access these files normally
&nbsp;
###  - **Command Prompt/PowerShell** 
-    will still show these files unless specifically filtered
&nbsp;

#### **Credits** 
*   Fork of Hide Dotfiles (Explorer only) by **@danalec** which was a fork of DotFiles by  **@thiagokokada**
*   Both are amazing developers who have some cool stuff! Check out their GitHub Profiles!
*   Also me TheShadyRainbow4 This was fun to develop and I learned a lot and plan to keep making / forking mods & help make windows more of what it should have always been! 
*   *I couldn't help but to also include some screenshots of my glorious Windows Vista Aero theme in the screenshots so here is one more ;)*
    
    &nbsp;
        &nbsp;
            &nbsp;
                                                    ![Screenshot](https://i.imgur.com/CdKAuRq.png)
*/
// ==/WindhawkModReadme==

// ==WindhawkModSettings==
/*
- displayMode: neverShow
  $name: Display Mode
  $description: How to handle dotfiles in directory listings
  $options:
  - neverShow: Never show files (completely hidden)
  - showAsHidden: Show files as hidden (with hidden attribute)
  - showAsSystem: Show files as system (with hidden+system attributes)
- dotfileWhitelist: [""]
  $name: Dotfile Whitelist
  $description: List of dotfile patterns to show
- alwaysHidecontextMenu: [""]
  $name: Always Hide
  $description: List of filename patterns to always hide regardless of dotfile status
- contextMenu:
  - enable: true
    $name: Enable context menu
    $description: Enable context menu features
  - title: "Toggle File Hiding"
    $name: Context menu text
- hotkey:
  - enable: true
    $name: Enable Hotkey
    $description: Registers a system-wide hotkey to toggle the mod.
  - ctrl: true
    $name: Ctrl
  - alt: true
    $name: Alt
  - shift: false
    $name: Shift
  - key: "H"
    $name: Key (e.g. "H", ";", ".")
*/
// ==/WindhawkModSettings==

#include <windows.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <winternl.h>
#include <vector>
#include <string>
#include <algorithm>
#include <strsafe.h>

// {D8A68228-A427-4664-870D-4706916F4545}
static const GUID CLSID_ToggleExplorerCommand = { 0xd8a68228, 0xa427, 0x4664, { 0x87, 0xd, 0x47, 0x6, 0x91, 0x6f, 0x45, 0x45 } };

// COM and module globals
long g_cRefThisDll = 0;
HINSTANCE g_hInst = NULL;
wchar_t g_modulePath[MAX_PATH];

// Mod state and settings globals
bool g_modEnabled = true;
bool g_enableContextMenu;
wchar_t g_contextMenuTitle[128];
bool g_hotkeyEnabled;
UINT g_hotkeyModifiers;
UINT g_hotkeyKey;
int g_hotkeyId = 1;

void Wh_ModUninit();
HRESULT RegisterPerUserComServer();  
HRESULT UnregisterPerUserComServer();


enum class DisplayMode {
    NeverShow,
    ShowAsHidden,
    ShowAsSystem
};

struct {
    DisplayMode displayMode = DisplayMode::NeverShow;
    std::vector<std::wstring> dotfileWhitelist;
    std::vector<std::wstring> alwaysHide;
} g_settings;

// DllMain to capture instance handle
BOOL WINAPI DllMain(HINSTANCE hInst, DWORD dwReason, LPVOID) {
    if (dwReason == DLL_PROCESS_ATTACH) {
        g_hInst = hInst;
        DisableThreadLibraryCalls(hInst);
    }
    return TRUE;
}

void InitModulePath() {
    GetModuleFileNameW(g_hInst, g_modulePath, ARRAYSIZE(g_modulePath));
}

// Registry helper functions
HRESULT RegisterPerUserComServer() {
    wchar_t clsidStr[39];
    if (!StringFromGUID2(CLSID_ToggleExplorerCommand, clsidStr, ARRAYSIZE(clsidStr))) {
        return E_FAIL;
    }

    wchar_t keyPath[MAX_PATH];
    HKEY hKey;

    // Create HKCU\Software\Classes\CLSID\{...}
    StringCchPrintfW(keyPath, ARRAYSIZE(keyPath), L"Software\\Classes\\CLSID\\%s", clsidStr);
    if (RegCreateKeyExW(HKEY_CURRENT_USER, keyPath, 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hKey, NULL) != ERROR_SUCCESS) {
        return E_FAIL;
    }
    RegSetValueExW(hKey, NULL, 0, REG_SZ, (const BYTE*)g_contextMenuTitle, (wcslen(g_contextMenuTitle) + 1) * sizeof(wchar_t));
    RegCloseKey(hKey);

    // Create HKCU\Software\Classes\CLSID\{...}\InprocServer32
    StringCchPrintfW(keyPath, ARRAYSIZE(keyPath), L"Software\\Classes\\CLSID\\%s\\InprocServer32", clsidStr);
    if (RegCreateKeyExW(HKEY_CURRENT_USER, keyPath, 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hKey, NULL) != ERROR_SUCCESS) {
        return E_FAIL;
    }
    RegSetValueExW(hKey, NULL, 0, REG_SZ, (const BYTE*)g_modulePath, (wcslen(g_modulePath) + 1) * sizeof(wchar_t));
    RegSetValueExW(hKey, L"ThreadingModel", 0, REG_SZ, (const BYTE*)L"Apartment", sizeof(L"Apartment"));
    RegCloseKey(hKey);
    
    // This is the key for IExplorerCommand handlers
    StringCchPrintfW(keyPath, ARRAYSIZE(keyPath), L"Software\\Classes\\AllFilesystemObjects\\ShellEx\\ContextMenuHandlers\\EnhancedFileHidingControl");
    if (RegCreateKeyExW(HKEY_CURRENT_USER, keyPath, 0, NULL, REG_OPTION_NON_VOLATILE, KEY_WRITE, NULL, &hKey, NULL) != ERROR_SUCCESS) {
        return E_FAIL;
    }
    RegSetValueExW(hKey, NULL, 0, REG_SZ, (const BYTE*)clsidStr, (wcslen(clsidStr) + 1) * sizeof(wchar_t));
    RegCloseKey(hKey);

    return S_OK;
}

HRESULT UnregisterPerUserComServer() {
    wchar_t clsidStr[39];
    if (!StringFromGUID2(CLSID_ToggleExplorerCommand, clsidStr, ARRAYSIZE(clsidStr))) {
        return E_FAIL;
    }

    RegDeleteKeyW(HKEY_CURRENT_USER, L"Software\\Classes\\AllFilesystemObjects\\ShellEx\\ContextMenuHandlers\\EnhancedFileHidingControl");
    
    wchar_t keyPath[MAX_PATH];
    StringCchPrintfW(keyPath, ARRAYSIZE(keyPath), L"Software\\Classes\\CLSID\\%s", clsidStr);
    SHDeleteKeyW(HKEY_CURRENT_USER, keyPath);

    return S_OK;
}

class ToggleExplorerCommand; // Forward declaration

template <class T>
class CClassFactory : public IClassFactory {
public:
    // IUnknown
    IFACEMETHODIMP QueryInterface(REFIID riid, void **ppv) {
        if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IClassFactory)) {
            *ppv = static_cast<IClassFactory *>(this);
        } else {
            *ppv = nullptr;
            return E_NOINTERFACE;
        }
        reinterpret_cast<IUnknown *>(*ppv)->AddRef();
        return S_OK;
    }
    IFACEMETHODIMP_(ULONG) AddRef() {
        return InterlockedIncrement(&m_ref);
    }
    IFACEMETHODIMP_(ULONG) Release() {
        long ref = InterlockedDecrement(&m_ref);
        if (ref == 0) {
            delete this;
        }
        return ref;
    }

    // IClassFactory
    IFACEMETHODIMP CreateInstance(IUnknown *pUnkOuter, REFIID riid, void **ppv) {
        if (pUnkOuter) {
            return CLASS_E_NOAGGREGATION;
        }
        T *pObject = new T;
        if (!pObject) {
            return E_OUTOFMEMORY;
        }
        HRESULT hr = pObject->QueryInterface(riid, ppv);
        pObject->Release();
        return hr;
    }
    IFACEMETHODIMP LockServer(BOOL fLock) {
        if (fLock) {
            InterlockedIncrement(&g_cRefThisDll);
        } else {
            InterlockedDecrement(&g_cRefThisDll);
        }
        return S_OK;
    }

    CClassFactory() : m_ref(1) { InterlockedIncrement(&g_cRefThisDll); }
    virtual ~CClassFactory() { InterlockedDecrement(&g_cRefThisDll); }
private:
    long m_ref;
};

class ToggleExplorerCommand : public IExplorerCommand, public IObjectWithSite {
public:
    // IUnknown
    IFACEMETHODIMP QueryInterface(REFIID riid, void **ppv) {
        static const QITAB qit[] = {
            QITABENT(ToggleExplorerCommand, IExplorerCommand),
            QITABENT(ToggleExplorerCommand, IObjectWithSite),
            { 0 },
        };
        return QISearch(this, qit, riid, ppv);
    }
    IFACEMETHODIMP_(ULONG) AddRef() {
        return InterlockedIncrement(&m_ref);
    }
    IFACEMETHODIMP_(ULONG) Release() {
        long ref = InterlockedDecrement(&m_ref);
        if (ref == 0) {
            delete this;
        }
        return ref;
    }

    // IExplorerCommand
    IFACEMETHODIMP GetTitle(IShellItemArray *psiItemArray, LPWSTR *ppszName) {
        return SHStrDupW(g_contextMenuTitle, ppszName);
    }
    IFACEMETHODIMP GetIcon(IShellItemArray *psiItemArray, LPWSTR *ppszIcon) { return E_NOTIMPL; }
    IFACEMETHODIMP GetToolTip(IShellItemArray *psiItemArray, LPWSTR *ppszInfotip) { return E_NOTIMPL; }
    IFACEMETHODIMP GetCanonicalName(GUID *pguidCommandName) { *pguidCommandName = CLSID_ToggleExplorerCommand; return S_OK; }
    IFACEMETHODIMP GetState(IShellItemArray *psiItemArray, BOOL fOkToBeSlow, EXPCMDSTATE *pCmdState) {
        *pCmdState = g_modEnabled ? ECS_CHECKED : ECS_ENABLED;
        return S_OK;
    }
    IFACEMETHODIMP Invoke(IShellItemArray *psiItemArray, IBindCtx *pbc) {
        g_modEnabled = !g_modEnabled;
        // The checkmark is not updated automatically.
        // A full explorer restart would be required to see the change in the checkmark state,
        // which is not user friendly.
        return S_OK;
    }
    IFACEMETHODIMP GetFlags(EXPCMDFLAGS *pFlags) { *pFlags = ECF_DEFAULT; return S_OK; }
    IFACEMETHODIMP EnumSubCommands(IEnumExplorerCommand **ppEnum) { *ppEnum = nullptr; return E_NOTIMPL; }

    // IObjectWithSite
    IFACEMETHODIMP SetSite(IUnknown *punkSite) {
        m_site = punkSite;
        return S_OK;
    }
    IFACEMETHODIMP GetSite(REFIID riid, void **ppv) {
        if (m_site) {
            return m_site->QueryInterface(riid, ppv);
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }

    ToggleExplorerCommand() : m_ref(1) { InterlockedIncrement(&g_cRefThisDll); }
    virtual ~ToggleExplorerCommand() { InterlockedDecrement(&g_cRefThisDll); }
private:
    long m_ref;
    IUnknown *m_site = nullptr;
};

// COM exports
extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID rclsid, REFIID riid, LPVOID *ppv) {
    if (!IsEqualCLSID(rclsid, CLSID_ToggleExplorerCommand)) {
        return CLASS_E_CLASSNOTAVAILABLE;
    }
    CClassFactory<ToggleExplorerCommand> *pcf = new CClassFactory<ToggleExplorerCommand>();
    if (!pcf) {
        return E_OUTOFMEMORY;
    }
    HRESULT hr = pcf->QueryInterface(riid, ppv);
    pcf->Release();
    return hr;
}

extern "C" HRESULT __stdcall DllCanUnloadNow(void) {
    return (g_cRefThisDll == 0) ? S_OK : S_FALSE;
}

typedef NTSTATUS (NTAPI* NtQueryDirectoryFile_t)(
    HANDLE FileHandle,
    HANDLE Event,
    PIO_APC_ROUTINE ApcRoutine,
    PVOID ApcContext,
    PIO_STATUS_BLOCK IoStatusBlock,
    PVOID FileInformation,
    ULONG Length,
    FILE_INFORMATION_CLASS FileInformationClass,
    BOOLEAN ReturnSingleEntry,
    PUNICODE_STRING FileName,
    BOOLEAN RestartScan
);

NtQueryDirectoryFile_t NtQueryDirectoryFile_Original;

typedef NTSTATUS (NTAPI* NtQueryDirectoryFileEx_t)(
    HANDLE FileHandle,
    HANDLE Event,
    PIO_APC_ROUTINE ApcRoutine,
    PVOID ApcContext,
    PIO_STATUS_BLOCK IoStatusBlock,
    PVOID FileInformation,
    ULONG Length,
    FILE_INFORMATION_CLASS FileInformationClass,
    ULONG QueryFlags,
    PUNICODE_STRING FileName
);

NtQueryDirectoryFileEx_t NtQueryDirectoryFileEx_Original;

UINT KeyNameToVk(const wchar_t* name) {
    if (!name || !*name) return 0;
    if (wcslen(name) == 1) {
        wchar_t c = towupper(name[0]);
        if ((c >= L'A' && c <= L'Z') || (c >= L'0' && c <= L'9')) {
            return c;
        }
    }
    if (name[0] == L'F' || name[0] == L'f') {
        int fkey = _wtoi(name + 1);
        if (fkey >= 1 && fkey <= 24) {
            return VK_F1 + (fkey - 1);
        }
    }
    if (_wcsicmp(name, L"Home") == 0) return VK_HOME;
    if (_wcsicmp(name, L"End") == 0) return VK_END;
    if (_wcsicmp(name, L"Insert") == 0) return VK_INSERT;
    if (_wcsicmp(name, L"Delete") == 0) return VK_DELETE;
    // Simple mapping for other common names could be added here
    return 0;
}

void ParseSettings() {
    g_settings.dotfileWhitelist.clear();
    g_settings.alwaysHide.clear();
    
    PCWSTR displayModeStr = Wh_GetStringSetting(L"displayMode");
    if (wcscmp(displayModeStr, L"showAsHidden") == 0) {
        g_settings.displayMode = DisplayMode::ShowAsHidden;
    } else if (wcscmp(displayModeStr, L"showAsSystem") == 0) {
        g_settings.displayMode = DisplayMode::ShowAsSystem;
    } else {
        g_settings.displayMode = DisplayMode::NeverShow;
    }
    Wh_FreeStringSetting(displayModeStr);

    // Context Menu settings
    g_enableContextMenu = Wh_GetIntSetting(L"contextMenu.enable");
    PCWSTR contextMenuTitleStr = Wh_GetStringSetting(L"contextMenu.title");
    StringCchCopyW(g_contextMenuTitle, ARRAYSIZE(g_contextMenuTitle), contextMenuTitleStr);
    Wh_FreeStringSetting(contextMenuTitleStr);

    // Hotkey settings
    g_hotkeyEnabled = Wh_GetIntSetting(L"hotkey.enable");
    g_hotkeyModifiers = 0;
    if (Wh_GetIntSetting(L"hotkey.ctrl")) {
        g_hotkeyModifiers |= MOD_CONTROL;
    }
    if (Wh_GetIntSetting(L"hotkey.alt")) {
        g_hotkeyModifiers |= MOD_ALT;
    }
    if (Wh_GetIntSetting(L"hotkey.shift")) {
        g_hotkeyModifiers |= MOD_SHIFT;
    }
    PCWSTR hotkeyKeyStr = Wh_GetStringSetting(L"hotkey.key");
    g_hotkeyKey = KeyNameToVk(hotkeyKeyStr);
    Wh_FreeStringSetting(hotkeyKeyStr);
    
    auto loadSettingList = [](const wchar_t* settingName, std::vector<std::wstring>& target) {
        for (int i = 0;; i++) {
            PCWSTR item = Wh_GetStringSetting(settingName, i);
            if (!*item) {
                Wh_FreeStringSetting(item);
                break;
            }
            if (item[0] != L'\0') {
                target.emplace_back(item);
            }
            Wh_FreeStringSetting(item);
        }
    };
    
    loadSettingList(L"dotfileWhitelist[%d]", g_settings.dotfileWhitelist);
    loadSettingList(L"alwaysHide[%d]", g_settings.alwaysHide);
}

bool ShouldHideFile(std::wstring_view fileName) noexcept {
    if (fileName.empty()) return false;
    
    if (fileName == L"." || fileName == L"..") {
        return false;
    }
    
    auto matchesPattern = [](std::wstring_view name, const std::vector<std::wstring>& patterns) noexcept -> bool {
        std::wstring temp(name);
        return std::ranges::any_of(patterns, [&temp](const std::wstring& pattern) {
            return PathMatchSpecW(temp.c_str(), pattern.c_str()) != FALSE;
        });
    };
    
    if (fileName[0] == L'.') {
        return !matchesPattern(fileName, g_settings.dotfileWhitelist);
    }
    
    return matchesPattern(fileName, g_settings.alwaysHide);
}

template<typename FileInfoType>
void FilterFilesInDirectory(void* FileInformation, ULONG_PTR* bytesReturned) noexcept {
    if (!FileInformation || !bytesReturned || *bytesReturned == 0) {
        return;
    }
    
    if (g_modEnabled && g_settings.displayMode == DisplayMode::NeverShow) {
        auto* currentEntry = static_cast<FileInfoType*>(FileInformation);
        auto* writeEntry = currentEntry;
        ULONG_PTR totalBytesRead = 0;
        ULONG_PTR totalBytesWritten = 0;
        
        const auto* const bufferEnd = reinterpret_cast<const BYTE*>(FileInformation) + *bytesReturned;
        
        while (totalBytesRead < *bytesReturned) {
            const ULONG nextEntryOffset = currentEntry->NextEntryOffset;
            const ULONG currentEntrySize = nextEntryOffset ? nextEntryOffset : (*bytesReturned - totalBytesRead);
            
            const ULONG fileNameLength = currentEntry->FileNameLength / sizeof(WCHAR);
            const std::wstring_view fileName(currentEntry->FileName, fileNameLength);
            
            const bool shouldHide = fileNameLength > 0 && ShouldHideFile(fileName);
            
            if (!shouldHide) {
                if (writeEntry != currentEntry) {
                    std::memmove(writeEntry, currentEntry, currentEntrySize);
                }
                totalBytesWritten += currentEntrySize;
                writeEntry = reinterpret_cast<FileInfoType*>(reinterpret_cast<BYTE*>(writeEntry) + currentEntrySize);
            }
            
            totalBytesRead += currentEntrySize;
            
            if (nextEntryOffset == 0 || 
                reinterpret_cast<const BYTE*>(currentEntry) + nextEntryOffset >= bufferEnd) {
                break;
            }
            
            currentEntry = reinterpret_cast<FileInfoType*>(
                reinterpret_cast<BYTE*>(currentEntry) + nextEntryOffset);
        }
        
        if (totalBytesWritten > 0) {
            auto* lastEntry = static_cast<FileInfoType*>(FileInformation);
            while (lastEntry->NextEntryOffset && 
                   reinterpret_cast<BYTE*>(lastEntry) + lastEntry->NextEntryOffset < 
                   reinterpret_cast<BYTE*>(FileInformation) + totalBytesWritten) {
                lastEntry = reinterpret_cast<FileInfoType*>(
                    reinterpret_cast<BYTE*>(lastEntry) + lastEntry->NextEntryOffset);
            }
            lastEntry->NextEntryOffset = 0;
        }
        
        *bytesReturned = totalBytesWritten;
    } else if constexpr (requires(FileInfoType t) { t.FileAttributes; }) {
            auto* currentEntry = static_cast<FileInfoType*>(FileInformation);
            ULONG_PTR totalBytesRead = 0;
            const auto* const bufferEnd = reinterpret_cast<const BYTE*>(FileInformation) + *bytesReturned;
            
            while (totalBytesRead < *bytesReturned) {
                const ULONG nextEntryOffset = currentEntry->NextEntryOffset;
                const ULONG currentEntrySize = nextEntryOffset ? nextEntryOffset : (*bytesReturned - totalBytesRead);
                
                const ULONG fileNameLength = currentEntry->FileNameLength / sizeof(WCHAR);
                const std::wstring_view fileName(currentEntry->FileName, fileNameLength);
                
                if (g_modEnabled && fileNameLength > 0 && ShouldHideFile(fileName)) {
                    DWORD newAttributes = 0;
                    switch (g_settings.displayMode) {
                        case DisplayMode::ShowAsHidden:
                            newAttributes = FILE_ATTRIBUTE_HIDDEN;
                            break;
                        case DisplayMode::ShowAsSystem:
                            newAttributes = FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM;
                            break;
                        default:
                            break;
                    }
                    
                    if (newAttributes != 0) {
                        currentEntry->FileAttributes |= newAttributes;
                    }
                }
                
                totalBytesRead += currentEntrySize;
                
                if (nextEntryOffset == 0 || 
                    reinterpret_cast<const BYTE*>(currentEntry) + nextEntryOffset >= bufferEnd) {
                    break;
                }
                
                currentEntry = reinterpret_cast<FileInfoType*>(
                    reinterpret_cast<BYTE*>(currentEntry) + nextEntryOffset);
            }
        }
}

void ProcessDirectoryListing(LPVOID FileInformation, FILE_INFORMATION_CLASS FileInformationClass, ULONG_PTR* bytesReturned) noexcept {
    switch (FileInformationClass) {
        case FileDirectoryInformation:
            FilterFilesInDirectory<FILE_DIRECTORY_INFORMATION>(FileInformation, bytesReturned);
            break;
        case FileFullDirectoryInformation:
            FilterFilesInDirectory<FILE_FULL_DIR_INFORMATION>(FileInformation, bytesReturned);
            break;
        case FileBothDirectoryInformation:
            FilterFilesInDirectory<FILE_BOTH_DIR_INFORMATION>(FileInformation, bytesReturned);
            break;
        case FileNamesInformation:
            FilterFilesInDirectory<FILE_NAMES_INFORMATION>(FileInformation, bytesReturned);
            break;
        case FileIdBothDirectoryInformation:
            FilterFilesInDirectory<FILE_ID_BOTH_DIR_INFORMATION>(FileInformation, bytesReturned);
            break;
        case FileIdFullDirectoryInformation:
            FilterFilesInDirectory<FILE_ID_FULL_DIR_INFORMATION>(FileInformation, bytesReturned);
            break;
        default:
            break;
    }
}

LRESULT CALLBACK HotkeyWindowProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    if (uMsg == WM_HOTKEY && wParam == (WPARAM)g_hotkeyId) {
        g_modEnabled = !g_modEnabled;
    }
    return DefWindowProc(hWnd, uMsg, wParam, lParam);
}

void Wh_ModUninit() {
    UnregisterPerUserComServer();
    UnregisterHotKey(NULL, g_hotkeyId);
    // No need to destroy the hotkey window, process is terminating.
}

NTSTATUS NTAPI NtQueryDirectoryFile_Hook(
    HANDLE FileHandle,
    HANDLE Event,
    PIO_APC_ROUTINE ApcRoutine,
    PVOID ApcContext,
    PIO_STATUS_BLOCK IoStatusBlock,
    PVOID FileInformation,
    ULONG Length,
    FILE_INFORMATION_CLASS FileInformationClass,
    BOOLEAN ReturnSingleEntry,
    PUNICODE_STRING FileName,
    BOOLEAN RestartScan) noexcept {
    
    const NTSTATUS status = NtQueryDirectoryFile_Original(
        FileHandle, Event, ApcRoutine, ApcContext, IoStatusBlock,
        FileInformation, Length, FileInformationClass,
        ReturnSingleEntry, FileName, RestartScan);
    
    if (g_modEnabled && NT_SUCCESS(status) && IoStatusBlock && FileInformation) {
        ULONG_PTR bytesReturned = IoStatusBlock->Information;
        ProcessDirectoryListing(FileInformation, FileInformationClass, &bytesReturned);
        IoStatusBlock->Information = bytesReturned;
    }
    
    return status;
}

NTSTATUS NTAPI NtQueryDirectoryFileEx_Hook(
    HANDLE FileHandle,
    HANDLE Event,
    PIO_APC_ROUTINE ApcRoutine,
    PVOID ApcContext,
    PIO_STATUS_BLOCK IoStatusBlock,
    PVOID FileInformation,
    ULONG Length,
    FILE_INFORMATION_CLASS FileInformationClass,
    ULONG QueryFlags,
    PUNICODE_STRING FileName) noexcept {
    
    const NTSTATUS status = NtQueryDirectoryFileEx_Original(
        FileHandle, Event, ApcRoutine, ApcContext, IoStatusBlock,
        FileInformation, Length, FileInformationClass,
        QueryFlags, FileName);
    
    if (g_modEnabled && NT_SUCCESS(status) && IoStatusBlock && FileInformation) {
        ULONG_PTR bytesReturned = IoStatusBlock->Information;
        ProcessDirectoryListing(FileInformation, FileInformationClass, &bytesReturned);
        IoStatusBlock->Information = bytesReturned;
    }
    
    return status;
}

BOOL Wh_ModInit() {
    InitModulePath();
    ParseSettings();

    // Create a message-only window to receive hotkey messages.
    WNDCLASSW wc = {};
    wc.lpfnWndProc = HotkeyWindowProc;
    wc.lpszClassName = L"EnhancedFileHidingControlHotkey";
    RegisterClassW(&wc);
    CreateWindowExW(0, wc.lpszClassName, NULL, 0, 0, 0, 0, 0, HWND_MESSAGE, NULL, NULL, NULL);

    if (g_hotkeyEnabled && g_hotkeyKey != 0) {
        RegisterHotKey(NULL, g_hotkeyId, g_hotkeyModifiers, g_hotkeyKey);
    }

    if (g_enableContextMenu) {
        RegisterPerUserComServer();
    }
    
    const HMODULE hNtDll = GetModuleHandleW(L"ntdll.dll");
    if (!hNtDll) {
        return FALSE;
    }
    
    NtQueryDirectoryFile_Original = reinterpret_cast<NtQueryDirectoryFile_t>(
        GetProcAddress(hNtDll, "NtQueryDirectoryFile"));
    NtQueryDirectoryFileEx_Original = reinterpret_cast<NtQueryDirectoryFileEx_t>(
        GetProcAddress(hNtDll, "NtQueryDirectoryFileEx"));
    
    if (!NtQueryDirectoryFile_Original || !NtQueryDirectoryFileEx_Original) {
        return FALSE;
    }
    
    return Wh_SetFunctionHook(reinterpret_cast<void*>(NtQueryDirectoryFile_Original), 
                              reinterpret_cast<void*>(NtQueryDirectoryFile_Hook), 
                              reinterpret_cast<void**>(&NtQueryDirectoryFile_Original)) &&
           Wh_SetFunctionHook(reinterpret_cast<void*>(NtQueryDirectoryFileEx_Original), 
                              reinterpret_cast<void*>(NtQueryDirectoryFileEx_Hook), 
                              reinterpret_cast<void**>(&NtQueryDirectoryFileEx_Original));
}

void Wh_ModSettingsChanged() {
    bool wasContextMenuEnabled = g_enableContextMenu;

    ParseSettings();
    
    // Unregister the old hotkey before registering the new one.
    UnregisterHotKey(NULL, g_hotkeyId);
    if (g_hotkeyEnabled && g_hotkeyKey != 0) {
        RegisterHotKey(NULL, g_hotkeyId, g_hotkeyModifiers, g_hotkeyKey);
    }

    // Handle context menu registration changes
    if (g_enableContextMenu != wasContextMenuEnabled) {
        if (g_enableContextMenu) {
            RegisterPerUserComServer();
        } else {
            UnregisterPerUserComServer();
        }
        // Let the user know they may need to restart Explorer
        MessageBoxW(NULL,   
            L"To apply the context menu changes, you may need to restart Windows Explorer.",  
            L"Context Menu Setting Changed",  
            MB_OK | MB_ICONINFORMATION);
    } 
    // If the menu is enabled and the title changed, re-register
    else if (g_enableContextMenu) {
        // Re-register to update the title in the registry
        RegisterPerUserComServer();
    }
}
