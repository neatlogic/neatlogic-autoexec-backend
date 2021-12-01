[Console]::OutputEncoding = [Text.Encoding]::UTF8;
[Console]::InputEncoding = [Text.Encoding]::UTF8;
Function getAllProcesses{
    Write-Output("PID PPID PGID USER %CPU MEMSIZE COMMAND COMMAND");
    foreach($process in Get-Process)
    {
        $processId = $process.id;
        $wmiObj = Get-WmiObject Win32_Process -Filter "ProcessId=$processId";
        if ( !$wmiObj ){
            continue;
        }

        $processName = $process.ProcessName;
        $userName = $process.UserName;
        $pcpu = [math]::Round($process.CPU, 2);
        $memSize = [math]::Round($process.WorkingSet64 / 1024 / 1024, 2);
        $command = $process.Path;

        $owner = $wmiObj.getOwner();
        $domain=$owner.Domain;
        $user=$owner.User;
        $parentPid = $wmiObj.ParentProcessId;
        $pgid = $wmiObj.SessionId;
        $cmdLine = $wmiObj.CommandLine;

        [Console]::Write("$processId $parentPid $pgid $user $pcpu $memSize $processName $cmdLine");
        Write-Output("")
    }
}