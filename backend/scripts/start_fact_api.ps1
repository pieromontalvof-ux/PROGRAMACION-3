param([int]$Workers=1,[switch]$Manual)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$php=Join-Path $projectRoot '.local/php/php.exe'
$python=Join-Path $projectRoot 'backend/.venv/Scripts/python.exe'
$service=Join-Path $projectRoot 'services/fact_api'
$runtime=Join-Path $projectRoot '.local'
if ($Workers -lt 1 -or $Workers -gt 4) {throw 'Usa entre 1 y 4 workers locales.'}
if (-not (Test-Path -LiteralPath (Join-Path $service '.env'))) {throw 'Ejecuta configure_fact_api.py primero.'}
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
if (-not (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 8091 -State Listen -ErrorAction SilentlyContinue)) {
    $process=Start-Process -FilePath $python -ArgumentList @('scripts/run_fact_api_service.py') -WorkingDirectory (Join-Path $projectRoot 'backend') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'fact-api.out.log') -RedirectStandardError (Join-Path $runtime 'fact-api.err.log')
    $process.Id | Set-Content (Join-Path $runtime 'fact-api.pid')
}
$workerProcesses=@(Get-CimInstance Win32_Process | Where-Object {$_.CommandLine -like '*run_fact_api_worker.py*' -and $_.Name -eq 'python.exe'})
$workerIds=@($workerProcesses | ForEach-Object {$_.ProcessId})
# Windows venv launchers have a second python child; count a worker only once.
$existing=@($workerProcesses | Where-Object {$_.ParentProcessId -notin $workerIds})
$supervisors=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'python.exe' -and $_.CommandLine -like '*run_fact_api_supervisor.py*'})
if (-not $Manual) {
    if (-not $supervisors.Count) {
        $manualWorkers=@($existing | Where-Object {$_.CommandLine -notlike '*--supervisor-id*'})
        if ($manualWorkers.Count) {throw 'Hay workers manuales activos. Ciérralos antes de iniciar el modo automático.'}
        $stopFile=Join-Path $runtime 'fact-supervisor.stop'
        if (Test-Path -LiteralPath $stopFile) {Remove-Item -LiteralPath $stopFile}
        $supervisor=Start-Process -FilePath $python -ArgumentList @('scripts/run_fact_api_supervisor.py','--min-workers',"$Workers",'--stop-file',$stopFile) -WorkingDirectory (Join-Path $projectRoot 'backend') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'fact-supervisor.out.log') -RedirectStandardError (Join-Path $runtime 'fact-supervisor.err.log')
        $supervisor.Id | Set-Content (Join-Path $runtime 'fact-supervisor.pid')
    }
    Write-Output 'fact_api DEMO. Workers automáticos entre el mínimo configurado y 4; sin interrupción de trabajos.'
    exit 0
}
if ($supervisors.Count) {throw 'El supervisor automático está activo. Deténlo antes de usar el modo manual.'}
for($i=$existing.Count;$i -lt $Workers;$i++) {
    $worker=Start-Process -FilePath $python -ArgumentList @('scripts/run_fact_api_worker.py') -WorkingDirectory (Join-Path $projectRoot 'backend') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime "fact-worker-$i.out.log") -RedirectStandardError (Join-Path $runtime "fact-worker-$i.err.log")
    $worker.Id | Set-Content (Join-Path $runtime "fact-worker-$i.pid")
}
Write-Output "fact_api DEMO en 127.0.0.1:8091. Workers solicitados: $Workers. Registros en .local."
