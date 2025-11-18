<a id="readme-top"></a>

<!-- EliteSoftware Co. LOGO -->

<br />
<div align="center">
<a href="Logo">
<img src="https://i.postimg.cc/85MDTcrJ/Elite-Software-LOGO-Mocup2.png" alt="Logo" width="256" height="256">
</a>
</div>

<!-- ABOUT THE PROJECT -->

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

<p align="right">(<a href="#readme-top">back to top</a>)</p>
