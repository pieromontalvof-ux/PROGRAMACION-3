// Isolated Chrome profile, public screens only; never uses the user's browser session.
import { spawn } from 'node:child_process'
import { mkdtemp, readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
const chromePath = process.env.CHROME_PATH ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe'
const url = process.argv[2] ?? 'http://127.0.0.1:5174'
const profile = await mkdtemp(resolve('../.local/chrome-memory-'))
const chrome = spawn(chromePath, ['--headless=new', '--no-first-run', '--disable-background-networking', '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], {windowsHide:true, stdio:'ignore'})
let socket
try {
  let port
  for(let i=0;i<100;i++) {try {port=Number((await readFile(resolve(profile,'DevToolsActivePort'),'utf8')).split('\n')[0]);break} catch {await delay(100)}}
  if(!port) throw new Error('Chrome no inició el puerto de diagnóstico')
  const tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json()
  socket = new WebSocket(tabs.find(tab=>tab.type==='page').webSocketDebuggerUrl)
  await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject})
  let id=0;const pending=new Map()
  socket.onmessage=({data})=>{const message=JSON.parse(data);const waiter=pending.get(message.id);if(waiter){pending.delete(message.id);if(message.error)waiter.reject(new Error(message.error.message));else waiter.resolve(message.result)}}
  const call=(method,params={})=>new Promise((resolve,reject)=>{const key=++id;pending.set(key,{resolve,reject});socket.send(JSON.stringify({id:key,method,params}))})
  await call('Page.enable');await call('Performance.enable')
  await call('Page.navigate',{url});await delay(2000)
  const measurements=[]
  // Warm the lazy modules before measuring retention.
  for(let batch=0;batch<4;batch++) {
    for(let cycle=0;cycle<10;cycle++) {
      for(const route of ['/salon','/login']) {
        await call('Runtime.evaluate',{expression:`history.pushState({},'',${JSON.stringify(route)});dispatchEvent(new PopStateEvent('popstate'))`})
        await delay(100)
      }
    }
    await call('HeapProfiler.collectGarbage')
    const {metrics}=await call('Performance.getMetrics')
    const values=Object.fromEntries(metrics.map(metric=>[metric.name,metric.value]))
    measurements.push({batch,heap_bytes:values.JSHeapUsedSize,documents:values.Documents,nodes:values.Nodes,event_listeners:values.JSEventListeners})
  }
  const result={scope:'Pantallas públicas de ingreso y acceso a salón, 40 ciclos; sin sesión autenticada ni operaciones comerciales.',measurements}
  await writeFile(resolve('../.local/browser-memory.json'),JSON.stringify(result,null,2))
  console.log(JSON.stringify(result,null,2))
  await call('Browser.close').catch(()=>{})
} finally {socket?.close();chrome.kill()}
