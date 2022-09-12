#Made by Alex Spurrell 9/1/2022
## Version 1.11
#Allows the use of flags with the script
param( 
    [Parameter(Mandatory, HelpMessage="Target IP for the scan")]
    [string]$IP,

    [Parameter(HelpMessage="Sets the path for the log file")]
    [string]$OUTPUT = "./NetworkRouteChangeLog.txt",

    [Parameter(HelpMessage="Setting this to an IP address seperate to the IP variable will effecively force a change to be detected. Useful for debugging")]
    [string]$TESTIP = "default",

    [Parameter(HelpMessage="Delay between each scan")]
    [string]$DELAY = 300000, #default 5 min delay

    [Parameter(HelpMessage="Displays help")]
    [Switch]$HELP
)

if($Help){
    Write-Host "Example: ./NetworkRouteChangeLogger.ps1 -IP 8.8.8.8 -OUTPUT './ScanOutput.txt' -DELAY 1000`n
    The TESTIP flag will introduce a second ip that it will alternate between each scan. This is purely for testing in order to introduce forced change detections, it most likely wont come into use for actual scans."
    return;
}

function TraceRoute {
    param (
        $Target
    )
        
        
    $output = tracert -h 10 $Target  | Out-String
    $output = $output -replace " {2,}", " " #Get rid of multiple spaces in a row

    $lines = $output.Split("`n");


    $traces = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^[ 	]{1,}[0-9].{1,}") { #only match lines that have data

            $line = $lines[$i] -ireplace '({{<[0-9]}|[0-9]{1,}) (ms)', '$1$2' #get rid of spacing in the ms
            $line = $line -ireplace '(^\s{1,})|[\[\]]', '' #get rid of starting space and brackets


            $trace = [PSCustomObject]@{
                number = -1
                times = @()
                address = ""
                ip = ""
            }

            $words = $line.Split(" ")
            $trace.number = $words[0]
            $trace.times += $words[1]
            $trace.times += $words[2]
            $trace.times += $words[3]


            if($words.Count -eq 6){
                $trace.ip = $words[4]
            } else {
                $trace.address = $words[4]
                $trace.ip = $words[5]
            }

            $traces += $trace;

        }
    }

return $traces
}



#$log = @() #Initialize an empty array

if(Test-Path $OUTPUT){ #Check if the log exists, if so, load it into the empty array
    #$log = Get-Content $OUTPUT -Raw | ConvertFrom-Json
} else {
    New-Item -Path $OUTPUT
}

$Last = $null; #Initialize the previous scan result variable

$Alt = $true #this changes from false to true back to false each loop. Useful for doing something every other loop.

while($true){ #inf loop
    $Alt = (-not $Alt)

    if ($null -eq $IP ){ #Checks if $IP flag is set, if not, close program.
        Write-Host "Please provide a Computername/IP for -IP"
        return;
    }

    $TraceIP = $IP;

    if("default" -ne $TESTIP){ # check if TESTIP is set, if so, alternate between the alt ip and the target ip
        if($Alt){
            $TraceIP = $TESTIP
        }
        else {
            $TraceIP = $IP
        }
    }
    $date = Get-Date -Format "HH:mm:ss"
    Write-Host "Running trace... $date" 
    #$trace = Test-NetConnection -ComputerName $TraceIP -TraceRoute #Run traceroute and store it. Similar to tracert in cmd
    $route = TraceRoute -Target $TraceIP

    $trace = @()
    for ($i = 0; $i -lt $route.Count; $i++) {
        $trace += $route[$i];
    }



    if($null -eq $Last){ #Check if this is the first scan we ran, if so, we can't compare so we just say first trace
        Write-Host "First trace"
        for($i = 0; $i -le $trace.Count; $i++){
            Write-Host $trace[$i].ip $trace[$i].times
        }
    } else{
        $change = $false; #Initialize change variable. 
        $change = ($Last.Count -ne $trace.Count) #Check if the route has a different number of hops, if so then we know the route is different
        $changeNote = "No change";
        $skip = $false;
        if($change){ $changeNote = "Route has different number of hops"}
        if(-not $change){ #If the number of hops is the same then we iterate through the current scan and compare each index to the previous, checking for differences
            for($i = 0; $i -le $trace.Count - 1; $i++){
                if(($Last[$i].ip -eq "0.0.0.0") -or ($trace[$i].ip -eq "0.0.0.0")){ # I had an issue where some of the hops would be 0.0.0.0 but then would be normal the next scan so I'm just skipping these for now.
                    break;
                    $skip = true;
                }
 
                if($Last[$i].ip -ne $trace[$i].ip ){ # compare the address step
                    $change = $true;
                    $changeNote = $i;
                    break;
                }
            }
        }

        if($change){
            Write-Host "CHANGE DETECTED"
            # Write-Host "Previous Trace:"
            # Write-Host $Last
            # Write-Host "Current Trace"
            # Write-Host $trace
            Write-Host $changeNote

            $bigger = @()
            #$smaller = @()
            if($Last.Count -gt $trace.Count){
                $bigger = $Last
                #$smaller = $trace
            } else {
                $bigger = $trace
                #$smaller = $Last
            }

            $i = 0;
            do{
                $color = "Green"
            try{
                if($i -ge $changeNote){
                    $color = "Red"
                }
            } catch{$color = "Red"}
                Write-Host "`t" $i "-----" $Last[$i].ip '('$Last[$i].times')' "-----"$trace[$i].ip '('$trace[$i].times')' "`n" -ForegroundColor $Color
                $i++;
            }until($null -eq $bigger[$i].ip)


            $compare = ""

            for($i = 0; $i -le $Last.Count; $i++) {
                if( $null -eq $Last[$i] -or $null -eq $trace[$i]){
                    continue;
                }
                if ($Last[$i].ip -eq $trace[$i].ip) {
                    $compare += $Last[$i].ip + $Last[$i].times + " " + " : " + $trace[$i].ip + " " + $trace[$i].times + "`n";
                } else {
                    $compare += "!!!" + $Last[$i].ip + " " + $Last[$i].times + " : " + $trace[$i].ip  + " " + $trace[$i].times + "!!!`n";
                }
            }

            # $log += ,[PSCustomObject]@{ #Save object in log
            #     Previous = [PSCustomObject]@{
            #         Host = $Last.Computername
            #         Time = Get-Date -Format "MM-dd-yyyy hh:mm:ss"
            #         Trace = $Last
            #     }
            #     Latest = [PSCustomObject]@{
            #         Host = $trace.Computername
            #         Time = Get-Date -Format "MM-dd-yyyy hh:mm:ss"
            #         Trace = $trace
            #     } 
            #     Compare = $compare
            # } #adding the traces to the log file

            # $log | ConvertTo-Json | Out-File $OUTPUT #storing them in a json file
            
            $time = Get-Date -Format "MM-dd-yyyy hh:mm:ss";
            
            ("Change detected at $time`n$compare-----------------------") | Out-File -Append -FilePath $OUTPUT 
        }
    }
    if(-not $skip) # if we skip the scan, we don't want to set this variable as it could lead to incorrect results.
        {$Last = $trace;}

    Write-Host "Waiting for $DELAY milliseconds"
    Start-Sleep -Milliseconds $DELAY
}