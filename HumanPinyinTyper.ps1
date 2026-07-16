Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$source = @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class NativeTyping {
    public const uint INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint KEYEVENTF_UNICODE = 0x0004;
    public const ushort VK_RETURN = 0x0D;
    public const ushort VK_TAB = 0x09;
    public const int WH_MOUSE_LL = 14;
    public const int WM_MBUTTONDOWN = 0x0207;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("kernel32.dll")]
    public static extern uint GetLastError();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr GetModuleHandle(string lpModuleName);

    public delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);
    public static event EventHandler MiddleMousePressed;
    private static LowLevelMouseProc mouseProc = MouseHookCallback;
    private static IntPtr mouseHook = IntPtr.Zero;

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)]
        public MOUSEINPUT mi;
        [FieldOffset(0)]
        public KEYBDINPUT ki;
        [FieldOffset(0)]
        public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    static INPUT UnicodeKey(char ch, bool up) {
        INPUT input = new INPUT();
        input.type = INPUT_KEYBOARD;
        input.U.ki.wScan = ch;
        input.U.ki.dwFlags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0);
        return input;
    }

    static INPUT VirtualKey(ushort vk, bool up) {
        INPUT input = new INPUT();
        input.type = INPUT_KEYBOARD;
        input.U.ki.wVk = vk;
        input.U.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
        return input;
    }

    public static bool SendUnicodeChar(char ch) {
        INPUT[] inputs = new INPUT[] {
            UnicodeKey(ch, false),
            UnicodeKey(ch, true)
        };
        return SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT))) == 2;
    }

    public static bool SendVirtualKey(ushort vk) {
        INPUT[] inputs = new INPUT[] {
            VirtualKey(vk, false),
            VirtualKey(vk, true)
        };
        return SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT))) == 2;
    }

    public static bool InstallMiddleMouseHook() {
        if (mouseHook != IntPtr.Zero) return true;

        using (Process currentProcess = Process.GetCurrentProcess())
        using (ProcessModule currentModule = currentProcess.MainModule) {
            mouseHook = SetWindowsHookEx(WH_MOUSE_LL, mouseProc, GetModuleHandle(currentModule.ModuleName), 0);
        }

        return mouseHook != IntPtr.Zero;
    }

    public static void UninstallMiddleMouseHook() {
        if (mouseHook == IntPtr.Zero) return;
        UnhookWindowsHookEx(mouseHook);
        mouseHook = IntPtr.Zero;
    }

    private static IntPtr MouseHookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && wParam.ToInt32() == WM_MBUTTONDOWN) {
            if (MiddleMousePressed != null) MiddleMousePressed(null, EventArgs.Empty);
            return new IntPtr(1);
        }

        return CallNextHookEx(mouseHook, nCode, wParam, lParam);
    }
}

public class UnicodeTyperForm : Form {
    public event EventHandler MiddleMousePressed;

    public UnicodeTyperForm() {
        NativeTyping.MiddleMousePressed += delegate(object sender, EventArgs e) {
            if (MiddleMousePressed != null) MiddleMousePressed(this, EventArgs.Empty);
        };
    }
}
"@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms

$script:isTyping = $false
$script:isLoading = $false
$script:isLoaded = $false
$script:loadedText = ""

function Get-DelayMs {
    param([char]$Character)

    $charsPerSecond = [Math]::Max(1, [int]$speedInput.Value)
    $baseDelay = [int][Math]::Round(1000 / $charsPerSecond)
    $jitter = [Math]::Max(3, [int]($baseDelay * 0.25))
    $base = Get-Random -Minimum ([Math]::Max(1, $baseDelay - $jitter)) -Maximum ($baseDelay + $jitter + 1)
    $punctuation = "，。；：！？、,.!?;:《》[]（）()"

    if ($Character -eq "`n") {
        return $base + ([int]($baseDelay * 4))
    }

    if ($punctuation.Contains([string]$Character)) {
        return $base + ([int]($baseDelay * 2))
    }

    return $base
}

function Set-ReadyState {
    param([bool]$Ready)

    $script:isLoaded = $Ready
    $startButton.Enabled = $Ready -and -not $script:isLoading
}

function Start-Loading {
    if ($script:isTyping -or $script:isLoading) {
        return
    }

    $content = $textBox.Text
    if ([string]::IsNullOrWhiteSpace($content)) {
        [System.Windows.Forms.MessageBox]::Show("请先输入需要自动输入的文本。", "没有文本") | Out-Null
        return
    }

    $script:isLoading = $true
    Set-ReadyState -Ready $false
    $loadButton.Enabled = $false
    $textBox.ReadOnly = $true
    $status.Text = "状态：正在加载 0/$($content.Length)"
    $form.Refresh()

    try {
        $unsupported = New-Object System.Collections.Generic.List[string]
        $chars = $content.ToCharArray()

        for ($i = 0; $i -lt $chars.Length; $i++) {
            $ch = $chars[$i]
            if ([char]::IsSurrogate($ch)) {
                $marker = "U+{0:X4}" -f [int]$ch
                if (-not $unsupported.Contains($marker)) {
                    $unsupported.Add($marker)
                }
            }

            if (($i % 50) -eq 0 -or $i -eq ($chars.Length - 1)) {
                $status.Text = "状态：正在加载 $($i + 1)/$($chars.Length)"
                [System.Windows.Forms.Application]::DoEvents()
            }
        }

        if ($unsupported.Count -gt 0) {
            [System.Windows.Forms.MessageBox]::Show("当前 Unicode 输入模式只支持基础平面字符。请移除 emoji 等不支持字符：`r`n$([string]::Join(', ', $unsupported))", "发现不支持字符") | Out-Null
            $status.Text = "状态：加载失败"
            return
        }

        $script:loadedText = $content
        Set-ReadyState -Ready $true
        $status.Text = "状态：加载完成，共 $($chars.Length) 个字符"
        [System.Windows.Forms.MessageBox]::Show("加载完成，已完成预演检查。现在可以点击目标输入框，然后按鼠标中键或[开始]。", "可以开始") | Out-Null
    }
    catch {
        $status.Text = "状态：加载失败"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "加载失败") | Out-Null
    }
    finally {
        $script:isLoading = $false
        $loadButton.Enabled = $true
        $textBox.ReadOnly = $false
        $startButton.Enabled = $script:isLoaded
    }
}

function Send-TextCharacter {
    param([char]$Character)

    if ($Character -eq "`r") {
        return
    }

    if ($Character -eq "`n") {
        if (-not [NativeTyping]::SendVirtualKey([NativeTyping]::VK_RETURN)) {
            throw "Enter failed. Win32 error: $([NativeTyping]::GetLastError())"
        }
        return
    }

    if ($Character -eq "`t") {
        if (-not [NativeTyping]::SendVirtualKey([NativeTyping]::VK_TAB)) {
            throw "Tab failed. Win32 error: $([NativeTyping]::GetLastError())"
        }
        return
    }

    if (-not [NativeTyping]::SendUnicodeChar($Character)) {
        throw "Unicode input failed while sending '$Character'. Win32 error: $([NativeTyping]::GetLastError())"
    }
}

function Start-Typing {
    if (-not $script:isLoaded -or $script:isLoading) {
        return
    }

    if ($script:isTyping) {
        $script:isTyping = $false
        $status.Text = "状态：正在停止..."
        return
    }

    $content = $script:loadedText
    if ([string]::IsNullOrWhiteSpace($content)) {
        [System.Windows.Forms.MessageBox]::Show("请先点击[加载]，完成后再开始。", "尚未加载") | Out-Null
        return
    }

    $script:isTyping = $true
    $startButton.Text = "停止"
    $loadButton.Enabled = $false
    $textBox.ReadOnly = $true
    $status.Text = "状态：3 秒后开始，请点击目标输入框..."
    $form.Refresh()
    Start-Sleep -Milliseconds 3000

    $chars = $content.ToCharArray()

    try {
        for ($i = 0; $i -lt $chars.Length; $i++) {
            if (-not $script:isTyping) {
                break
            }

            Send-TextCharacter -Character $chars[$i]
            $status.Text = "状态：正在输入 $($i + 1)/$($chars.Length)"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds (Get-DelayMs -Character $chars[$i])
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "输入失败") | Out-Null
    }

    $script:isTyping = $false
    $startButton.Text = "开始"
    $loadButton.Enabled = $true
    $textBox.ReadOnly = $false
    $status.Text = "状态：空闲"
}

$form = New-Object UnicodeTyperForm
$form.Text = "Unicode 自动输入工具"
$form.Size = New-Object System.Drawing.Size(760, 590)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = "在下方输入文本，先点击[加载]完成预演检查，再点击目标输入框并按鼠标中键或[开始]。"
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(14, 14)
$form.Controls.Add($title)

$note = New-Object System.Windows.Forms.Label
$note.Text = "使用 Unicode 键盘输入，不使用剪贴板，也不依赖拼音输入法；部分受保护网页仍可能拦截模拟输入。"
$note.AutoSize = $true
$note.Location = New-Object System.Drawing.Point(14, 40)
$form.Controls.Add($note)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Multiline = $true
$textBox.ScrollBars = "Vertical"
$textBox.AcceptsReturn = $true
$textBox.AcceptsTab = $true
$textBox.WordWrap = $true
$textBox.Location = New-Object System.Drawing.Point(14, 72)
$textBox.Size = New-Object System.Drawing.Size(714, 380)
$form.Controls.Add($textBox)

$textBox.Add_TextChanged({
    if (-not $script:isLoading -and -not $script:isTyping) {
        $script:loadedText = ""
        Set-ReadyState -Ready $false
        $status.Text = "状态：文本已变化，请重新加载"
    }
})

$status = New-Object System.Windows.Forms.Label
$status.Text = "状态：未加载"
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(14, 460)
$form.Controls.Add($status)

$settingsGroup = New-Object System.Windows.Forms.GroupBox
$settingsGroup.Text = "控制与设置"
$settingsGroup.Location = New-Object System.Drawing.Point(14, 486)
$settingsGroup.Size = New-Object System.Drawing.Size(340, 42)
$form.Controls.Add($settingsGroup)

$speedLabel = New-Object System.Windows.Forms.Label
$speedLabel.Text = "打字速度："
$speedLabel.AutoSize = $true
$speedLabel.Location = New-Object System.Drawing.Point(12, 17)
$settingsGroup.Controls.Add($speedLabel)

$speedInput = New-Object System.Windows.Forms.NumericUpDown
$speedInput.Minimum = 1
$speedInput.Maximum = 200
$speedInput.Value = 10
$speedInput.Increment = 5
$speedInput.Location = New-Object System.Drawing.Point(86, 14)
$speedInput.Width = 70
$settingsGroup.Controls.Add($speedInput)

$speedUnit = New-Object System.Windows.Forms.Label
$speedUnit.Text = "字符/秒"
$speedUnit.AutoSize = $true
$speedUnit.Location = New-Object System.Drawing.Point(164, 17)
$settingsGroup.Controls.Add($speedUnit)

$loadButton = New-Object System.Windows.Forms.Button
$loadButton.Text = "加载"
$loadButton.Location = New-Object System.Drawing.Point(456, 492)
$loadButton.Size = New-Object System.Drawing.Size(110, 34)
$form.Controls.Add($loadButton)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "开始"
$startButton.Location = New-Object System.Drawing.Point(585, 492)
$startButton.Size = New-Object System.Drawing.Size(143, 34)
$startButton.Enabled = $false
$form.Controls.Add($startButton)

$loadButton.Add_Click({ Start-Loading })
$startButton.Add_Click({ Start-Typing })
$form.add_MiddleMousePressed({ Start-Typing })

$form.Add_Shown({
    $ok = [NativeTyping]::InstallMiddleMouseHook()
    if (-not $ok) {
        [System.Windows.Forms.MessageBox]::Show("鼠标中键监听失败。仍可使用[开始]按钮。", "鼠标监听") | Out-Null
    }
})

$form.Add_FormClosing({
    [NativeTyping]::UninstallMiddleMouseHook()
})

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
