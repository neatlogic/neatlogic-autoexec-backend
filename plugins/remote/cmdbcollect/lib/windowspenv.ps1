[Console]::OutputEncoding = [Text.Encoding]::UTF8;
[Console]::InputEncoding = [Text.Encoding]::UTF8;
Function getProcessEnv($processId){
    $process = Get-Process -ID $processId;
    $env = "";
    foreach($entry in $process.StartInfo.EnvironmentVariables){
        $name = $entry.Name.ToUpper();
        $val = $entry.Value;
        $env = "$env $name=$val";
    }
    Write-Output("PID:$processId environment");
    [Console]::Write($env);
    Write-Output("");
}
