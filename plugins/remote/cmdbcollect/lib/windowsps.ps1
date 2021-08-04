[Console]::OutputEncoding = [Text.Encoding]::UTF8;
[Console]::InputEncoding = [Text.Encoding]::UTF8;
Function getAllProcesses{
    Write-Output("PID PPID PGID USER TIME COMMAND COMMAND");
    foreach($process in Get-Process)
    {
        $processId = $process.id;
        $wmiObj = Get-WmiObject Win32_Process -Filter "ProcessId=$processId";

        $processName = $process.ProcessName;
        $userName = $process.UserName;
        $cpuTime = $process.TotalProcessorTime;
        $command = $process.Path;

        $owner = $wmiObj.getOwner();
        $domain=$owner.Domain;
        $user=$owner.User;
        $parentPid = $wmiObj.ParentProcessId;
        $pgid = $wmiObj.SessionId;
        $cmdLine = $wmiObj.CommandLine;

        [Console]::Write("$processId $parentPid $pgid $user $cpuTime $processName $cmdLine");
        Write-Output("")
    }
}