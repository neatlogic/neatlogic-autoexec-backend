Function getAllProcesses{
    #ps -eo pid,ppid,pgid,user,group,ruser,rgroup,pcpu,pmem,time,etime,comm,args
    Write-Output("PID PPID PGID USER TIME COMMAND COMMAND");
    foreach($process in Get-Process)
    {
        $processId = $process.id;
        $processName = $process.ProcessName;
        $userName = $process.UserName;
        $cpuTime = $process.TotalProcessorTime;
        $command = $process.Path;
        $wmiObj = Get-WmiObject Win32_Process -Filter "ProcessId=$processId";
        $parentPid = $wmiObj.ParentProcessId;
        $pgid = $wmiObj.SessionId;
        $cmdLine = $wmiObj.CommandLine;
        $domain=$wmiObj.getOwner().Domain;
        $user=$wmiObj.getOwner().User;

        Write-output "$processId $parentPid $pgid $user $cpuTime $processName $cmdLine";
        $process.StartInfo.Environment;
    }
}