Function getProcessEnv($processId){
    #$processId = $ARGS[0];
    $process = Get-Process -ID $processId;
    $env = "";
    foreach($entry in $process.StartInfo.EnvironmentVariables){
        $name = $entry.Name;
        $val = $entry.Value;
        $env = "$env $name=$val";
    }
    Write-Output("PID:$processId environment");
    Write-Output($env);
}
