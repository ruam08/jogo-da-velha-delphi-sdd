# Envia Ctrl+C ao console de um processo (prova de conceito da Entrega O0).
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File send-ctrl-c.ps1 -ProcessId <pid>
# Código de saída: 0 = enviado; 10 = não conseguiu se ligar ao console; 20 = falha ao gerar o evento.
# Deve rodar num processo PowerShell separado: ele se desliga do próprio console
# para se ligar ao console do processo alvo.
param([Parameter(Mandatory = $true)][int]$ProcessId)

$source = @'
using System;
using System.Runtime.InteropServices;
public static class SpikeConsole {
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool FreeConsole();
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool AttachConsole(uint processId);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GenerateConsoleCtrlEvent(uint ctrlEvent, uint processGroupId);
}
'@
Add-Type -TypeDefinition $source

[void][SpikeConsole]::FreeConsole()
if (-not [SpikeConsole]::AttachConsole([uint32]$ProcessId)) { exit 10 }
# Este processo ignora o próprio Ctrl+C, que também chega a ele.
[void][SpikeConsole]::SetConsoleCtrlHandler([IntPtr]::Zero, $true)
$sent = [SpikeConsole]::GenerateConsoleCtrlEvent(0, 0)   # 0 = CTRL_C_EVENT para todo o console
Start-Sleep -Milliseconds 300
[void][SpikeConsole]::FreeConsole()
if ($sent) { exit 0 } else { exit 20 }
