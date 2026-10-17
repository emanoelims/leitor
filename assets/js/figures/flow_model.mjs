// Pure, deterministic simulation. Geometry and UI read this same state.
export function createFlow(blueprint) {
  return {time:0, clock:0, automatic:true, nextId:1, accepted:0, completed:0, rejected:0,
    queue:[], delivered:[], stations:blueprint.stages.map(stage=>({...stage, enabled:true, item:null, elapsed:0})),
    limit:blueprint.queue_limit, interval:blueprint.arrival_seconds}
}

export function enqueue(state, count=1) {
  for (let i=0;i<count;i++) {
    if (state.queue.length>=state.limit) {state.rejected++; continue}
    state.queue.push({id:state.nextId++}); state.accepted++
  }
}

export function advance(state, seconds) {
  let left=Math.max(0, Math.min(seconds, 10))
  while (left>1e-8) {
    const dt=Math.min(left, 1/120); left-=dt; state.time+=dt
    if (state.automatic) {
      state.clock+=dt
      if (state.clock>=state.interval) {state.clock-=state.interval; enqueue(state)}
    }
    for (let i=state.stations.length-1;i>=0;i--) {
      const station=state.stations[i]
      if (!station.enabled) continue
      if (station.item) {
        station.elapsed=Math.min(station.seconds, station.elapsed+dt)
        if (station.elapsed+1e-8>=station.seconds) {
          const next=state.stations[i+1]
          if (!next || !next.item) {
            if (next) {next.item=station.item; next.elapsed=0}
            else {state.completed++;state.delivered.push({...station.item,time:state.time})}
            station.item=null; station.elapsed=0
          }
        }
      }
      if (i===0 && !station.item && state.queue.length) {station.item=state.queue.shift(); station.elapsed=0}
    }
  }
  state.delivered=state.delivered.filter(item=>state.time-item.time<1).slice(-3)
  return state
}

export const occupancy = state => state.stations.filter(s=>s.item).length
