// ---- GTFS BUS DATABASE (COMPACT) ----
var _gtfsDB = null;
var _busStopMarkerList = [];
var _busNavData = null;
var _busOsrmCoords = null;
var _busOsrmCoordsReturn = null;
var _busSearchReqId = 0;
var _busSearchTimer = null;

function _timeToMin(t) {
  if (!t || t.length < 5) return 0;
  return parseInt(t.substring(0,2)) * 60 + parseInt(t.substring(3,5));
}
function _minToTime(m) {
  m = (Math.round(m) + 1440) % 1440;
  var h = Math.floor(m/60), mn = m%60;
  return (h<10?'0':'')+h+':'+(mn<10?'0':'')+mn;
}
function _patternStop(sl, sr, so, depTime, stopIdx) {
  var depMin = _timeToMin(depTime);
  var stop = sl[sr[stopIdx]], off = so[stopIdx];
  return { name: stop[0], lat: stop[1], lon: stop[2],
    arrival: _minToTime(depMin + off[0]),
    departure: _minToTime(depMin + off[1]) };
}
function _patternStops(sl, sr, so, depTime) {
  var depMin = _timeToMin(depTime);
  var result = [];
  for (var i = 0; i < sr.length; i++) {
    var stop = sl[sr[i]], off = so[i];
    result.push({ name: stop[0], lat: stop[1], lon: stop[2],
      arrival: _minToTime(depMin + off[0]),
      departure: _minToTime(depMin + off[1]) });
  }
  return result;
}
var _SVC_MAP = {'F':'Feriale','S':'Sabato','D':'Domenica'};
function _fmtServiceCompact(patterns) {
  var uniq = [];
  for (var pi = 0; pi < patterns.length; pi++) {
    var s = _SVC_MAP[patterns[pi].s] || patterns[pi].s;
    if (s && uniq.indexOf(s) === -1) uniq.push(s);
  }
  if (uniq.length === 0) return "";
  if (uniq.length === 1) return " · " + uniq[0];
  if (uniq.indexOf("Feriale") !== -1) return " · Feriale";
  return " · " + uniq.join(" e ");
}

function loadGtfsDatabase(jsonStr) {
  try {
    _gtfsDB = JSON.parse(jsonStr);
    var count = Object.keys(_gtfsDB.lines).length;
    appLog("✅ GTFS compact DB: " + count + " lines, " + _gtfsDB.sl.length + " stops, " + _gtfsDB.sh.length + " shapes, " + _gtfsDB.sh.length + " shapes");
  } catch(e) { appLog("❌ GTFS parse: " + e.message); }
}
function loadGtfsDatabaseBase64(b64) {
  try { loadGtfsDatabase(atob(b64)); } catch(e) { appLog("❌ GTFS b64: " + e.message); }
}

function nativeSearchBusLine(query) {
  try {
    query = (query || "").trim().toUpperCase();
    if (query.length < 1) return;
    if (_busSearchTimer) { clearTimeout(_busSearchTimer); _busSearchTimer = null; }
    if (!_gtfsDB) {
      try { webkit.messageHandlers.requestGtfs.postMessage(""); } catch(e) {}
      appLog("⏳ GTFS DB non caricato, richiedo...");
      _busSearchTimer = setTimeout(function(){nativeSearchBusLine(query);},500);
      return;
    }
    var sl = _gtfsDB.sl, reqId = ++_busSearchReqId, results = [];
    var keys = Object.keys(_gtfsDB.lines);
    for (var ki = 0; ki < keys.length; ki++) {
      if (reqId !== _busSearchReqId) return;
      try {
        var ln = keys[ki];
        if (ln !== query && ln.indexOf(query+'_') !== 0) continue;
        var line = _gtfsDB.lines[ln];
        if (!line || !line.patterns || !line.patterns.length) continue;
        var serviceLabel = _fmtServiceCompact(line.patterns);
        var firstPat = null;
        for (var pi = 0; pi < line.patterns.length; pi++) {
          if (line.patterns[pi].d === 0) { firstPat = line.patterns[pi]; break; }
        }
        if (!firstPat) firstPat = line.patterns[0];
        if (!firstPat) continue;
        var fs = sl[firstPat.sr[0]];
        if (!fs) continue;
        var allHeadsigns = [];
        for (var pi = 0; pi < line.patterns.length; pi++) {
          var h = line.patterns[pi].h || "";
          if (h && allHeadsigns.indexOf(h) === -1) allHeadsigns.push(h);
        }
        results.push({
          displayName: "Linea " + ln + serviceLabel,
          displaySubtitle: allHeadsigns.join(" — ") + " (" + firstPat.sr.length + " fermate)",
          name: ln, lat: fs[1], lon: fs[2], lineNumber: ln,
          direction: firstPat.d, stopCount: firstPat.sr.length,
          dist: distance(userLat, userLng, fs[1], fs[2])
        });
      } catch(ee) { appLog("⚠️ Skipping " + keys[ki] + ": " + (ee.message||"")); }
    }
    if (reqId !== _busSearchReqId) return;
    results.sort(function(a,b){return a.dist-b.dist;});
    _lastSearchResults = results;
    try { webkit.messageHandlers.searchResults.postMessage(results); } catch(e) {}
    appLog("✅ Bus search '" + query + "': " + results.length + " risultati");
  } catch(e) { appLog("❌ nativeSearchBusLine error: " + e.message); }
}

function nativeSearchBusLineByTime(query, hour, min, dayIndex) {
  try {
    query = (query || "").trim().toUpperCase();
    if (query.length < 1) return;
    hour = parseInt(hour)||0; min = parseInt(min)||0; dayIndex = parseInt(dayIndex)||0;
    var dayServiceCompact = (['F','F','F','F','F','S','D'])[dayIndex >= 0 && dayIndex < 7 ? dayIndex : 0];
    var isFullDay = (hour === 0 && min === 0);
    if (_busSearchTimer) { clearTimeout(_busSearchTimer); _busSearchTimer = null; }
    if (!_gtfsDB) {
      try { webkit.messageHandlers.requestGtfs.postMessage(""); } catch(e) {}
      appLog("⏳ GTFS DB non caricato, richiedo...");
      _busSearchTimer = setTimeout(function(){nativeSearchBusLineByTime(query,hour,min);},500);
      return;
    }
    var sl = _gtfsDB.sl, reqId = ++_busSearchReqId, results = [];
    var keys = Object.keys(_gtfsDB.lines);
    for (var ki = 0; ki < keys.length; ki++) {
      if (reqId !== _busSearchReqId) return;
      try {
        var ln = keys[ki];
        if (ln !== query && ln.indexOf(query+'_') !== 0) continue;
        var line = _gtfsDB.lines[ln];
        if (!line || !line.patterns || !line.patterns.length) continue;
        var serviceLabel = _fmtServiceCompact(line.patterns);
        for (var pi = 0; pi < line.patterns.length; pi++) {
          if (reqId !== _busSearchReqId) return;
          try {
            var pat = line.patterns[pi];
            if (pat.s !== dayServiceCompact) continue;
            var depTimes = pat.t;
            for (var ti = 0; ti < depTimes.length; ti++) {
              if (reqId !== _busSearchReqId) return;
              try {
                var dep = depTimes[ti];
                if (!dep || dep.length < 5) continue;
                if (!isFullDay) {
                  var depTotal = _timeToMin(dep);
                  var startTotal = hour*60+min;
                  if (depTotal < startTotal || depTotal > startTotal+30) continue;
                }
                var fs = sl[pat.sr[0]];
                results.push({
                  displayName: dep + "  Linea " + ln + serviceLabel,
                  displaySubtitle: pat.h + " (" + pat.sr.length + " fermate)",
                  name: ln, lat: fs[1], lon: fs[2], lineNumber: ln,
                  direction: pat.d, departure: dep,
                  dirLabel: (pat.d===0?"Andata":"Ritorno"),
                  stopCount: pat.sr.length,
                  _patIdx: pi, _tripIdx: ti
                });
              } catch(ee) {}
            }
          } catch(ee) {}
        }
      } catch(ee) { appLog("⚠️ Skipping " + keys[ki] + ": " + (ee.message||"")); }
    }
    if (reqId !== _busSearchReqId) return;
    results.sort(function(a,b){return _timeToMin(a.departure)-_timeToMin(b.departure);});
    _lastSearchResults = results;
    try { webkit.messageHandlers.searchResults.postMessage(results); } catch(e) {}
    appLog("✅ Bus search '" + query + "': " + results.length + " risultati" + (isFullDay?" (full day)":" @"+hour+":"+min+" +30min"));
  } catch(e) { appLog("❌ nativeSearchBusLineByTime error: " + e.message); }
}

function selectBusLine(lineNum, dir, patIdx, tripIdx) {
  appLog("🗺️ selectBusLine(" + lineNum + "," + dir + "," + patIdx + "," + tripIdx + ")");
  clearRoute(); clearDestination(); clearBusRouteLayers();
  if (!_gtfsDB) {
    try { webkit.messageHandlers.requestGtfs.postMessage(""); } catch(e) {}
    setTimeout(function(){selectBusLine(lineNum,dir);},500);
    return;
  }
  var sl = _gtfsDB.sl, sh = _gtfsDB.sh;
  var line = _gtfsDB.lines[lineNum];
  if (!line || !line.patterns) { appLog("❌ line '" + lineNum + "' not found"); return; }
  var pat = null;
  if (patIdx !== undefined && patIdx !== null && line.patterns[patIdx] && line.patterns[patIdx].d === dir) {
    pat = line.patterns[patIdx];
  } else {
    for (var i = 0; i < line.patterns.length; i++) { if (line.patterns[i].d === dir) { pat = line.patterns[i]; break; } }
  }
  if (!pat) { appLog("❌ no pattern for dir " + dir); return; }
  var tIdx = (tripIdx !== undefined && tripIdx !== null && tripIdx < pat.t.length) ? tripIdx : 0;
  var depTime = pat.t[tIdx];
  var tripStops = _patternStops(sl, pat.sr, pat.so, depTime);
  var returnPat = null;
  for (var i = 0; i < line.patterns.length; i++) { if (line.patterns[i].d !== dir) { returnPat = line.patterns[i]; break; } }
  var returnStops = returnPat ? _patternStops(sl, returnPat.sr, returnPat.so, returnPat.t[0]) : null;
  var trip = {
    dir: pat.d, headsign: pat.h, service: _SVC_MAP[pat.s]||pat.s,
    departure: depTime, stops: tripStops,
    shape: sh[pat.sh] || [],
    lat: tripStops[0].lat, lon: tripStops[0].lon, stopCount: tripStops.length
  };
  appLog("✅ pattern: stops=" + tripStops.length + ", dep=" + depTime + ", return=" + (returnStops?returnStops.length:0));
  stopNavEngine();
  var coords = tripStops.map(function(s){return [s.lon, s.lat];});
  var drawOk = false;
  try {
    ['route-line','route-line-v2','bus-route','bus-route-v1','bus-route-v2'].forEach(function(id){try{map.removeLayer(id);}catch(e){}try{map.removeSource(id);}catch(e){}});
    map.addSource('bus-route-v1',{type:'geojson',data:{type:'Feature',geometry:{type:'LineString',coordinates:coords}}});
    map.addLayer({id:'bus-route-v1',type:'line',source:'bus-route-v1',layout:{'line-join':'round','line-cap':'round'},paint:{'line-color':'#22cc44','line-width':6,'line-opacity':0.9}});
    try{map.moveLayer('user-location-layer');}catch(ee){}
    try{map.moveLayer('user-location-ring');}catch(ee){}
    var lastC = coords[coords.length-1];
    try{if(markerDest){markerDest.remove();markerDest=null;}}catch(e){}
    var el=document.createElement('div'); el.style.cssText="width:16px;height:16px;border-radius:50%;background:#e74c3c;border:3px solid #fff;box-shadow:0 2px 8px rgba(0,0,0,0.5)";
    markerDest=new maplibregl.Marker({element:el,anchor:'center'}).setLngLat(lastC).addTo(map);
    try{var b=new maplibregl.LngLatBounds();coords.forEach(function(c){b.extend(c);});var c=b.getCenter();map.jumpTo({center:[c.lng,c.lat],zoom:11,pitch:0});}catch(e){}
    drawOk=true;
  } catch(e){appLog("❌ bus-route-v1: "+e.message);}
  if(drawOk){
    _clearBusStopMarkers();
    tripStops.forEach(function(s,idx){
      var el=document.createElement('div');
      var style="width:14px;height:14px;border-radius:50%;background:#22cc44;border:2px solid #fff;cursor:pointer;";
      if(idx===0||idx===tripStops.length-1) style="width:18px;height:18px;border-radius:50%;background:#e74c3c;border:3px solid #fff;cursor:pointer;";
      el.style.cssText=style; el.title=s.name;
      var popup = s.name + "<br/>arrivo: " + s.arrival + " - partenza: " + s.departure;
      var m=new maplibregl.Marker({element:el,anchor:'center'}).setLngLat([s.lon,s.lat]).setPopup(new maplibregl.Popup({offset:10}).setHTML(popup)).addTo(map);
      _busStopMarkerList.push(m);
    });
    if(returnStops&&returnStops.length>=2){
      returnStops.forEach(function(s,idx){
        var el=document.createElement('div');
        var style="width:12px;height:12px;border-radius:50%;background:#cc2222;border:2px solid #fff;cursor:pointer;";
        if(idx===0||idx===returnStops.length-1) style="width:16px;height:16px;border-radius:50%;background:#cc2222;border:3px solid #fff;cursor:pointer;";
        el.style.cssText=style; el.title=s.name;
        var m=new maplibregl.Marker({element:el,anchor:'center'}).setLngLat([s.lon,s.lat]).setPopup(new maplibregl.Popup({offset:10}).setText(s.name)).addTo(map);
        _busStopMarkerList.push(m);
      });
    }
    _busNavData={line:lineNum,dir:dir,trip:trip,returnStops:returnStops};
    var wps=tripStops.map(function(s){return s.lon+","+s.lat;}).join(";");
    var url=OSRM_URL+"/route/v1/driving/"+wps+"?geometries=geojson&overview=full&alternatives=false";
    var ctrl=new AbortController(); var to=setTimeout(function(){ctrl.abort();},10000);
    fetch(url,{signal:ctrl.signal}).then(function(r){return r.json();}).then(function(data){
      clearTimeout(to);
      if(data&&data.routes&&data.routes[0]){
        var rc=data.routes[0].geometry.coordinates;
        try{map.getSource('bus-route-v1').setData({type:'Feature',geometry:{type:'LineString',coordinates:rc}});}catch(ee){}
        try{var bb=new maplibregl.LngLatBounds();rc.forEach(function(c){bb.extend(c);});map.fitBounds(bb,{padding:80,pitch:50,maxZoom:16});}catch(ee){}
        try{if(markerDest)markerDest.setLngLat(rc[rc.length-1]);}catch(ee){}
        _busOsrmCoords=rc;
      } else { _busOsrmCoords=null; }
    }).catch(function(err){clearTimeout(to);_busOsrmCoords=null;});
    if(returnStops&&returnStops.length>=2){
      var rwps=returnStops.map(function(s){return s.lon+","+s.lat;}).join(";");
      var rurl=OSRM_URL+"/route/v1/driving/"+rwps+"?geometries=geojson&overview=full&alternatives=false";
      var rctrl=new AbortController(); var rto=setTimeout(function(){rctrl.abort();},10000);
      fetch(rurl,{signal:rctrl.signal}).then(function(r){return r.json();}).then(function(data){
        clearTimeout(rto);
        if(data&&data.routes&&data.routes[0]){
          var rc=data.routes[0].geometry.coordinates;
          try{map.addSource('bus-route-v2',{type:'geojson',data:{type:'Feature',geometry:{type:'LineString',coordinates:rc}}});map.addLayer({id:'bus-route-v2',type:'line',source:'bus-route-v2',paint:{'line-color':'#cc2222','line-width':4,'line-opacity':0.6}});try{map.moveLayer('user-location-layer');}catch(ee){}try{map.moveLayer('user-location-ring');}catch(ee){}}catch(ee){}
          _busOsrmCoordsReturn=rc;
        }
      }).catch(function(err){
        clearTimeout(rto);
        try{var rs=(sh[returnPat.sh]||[]).map(function(p){return[p[1],p[0]];});if(rs.length>=2){map.addSource('bus-route-v2',{type:'geojson',data:{type:'Feature',geometry:{type:'LineString',coordinates:rs}}});map.addLayer({id:'bus-route-v2',type:'line',source:'bus-route-v2',paint:{'line-color':'#cc2222','line-width':4,'line-opacity':0.6}});try{map.moveLayer('user-location-layer');}catch(ee){}try{map.moveLayer('user-location-ring');}catch(ee){}}}catch(ee){}
      });
    }
    setTimeout(function(){pushPosition(userLat,userLng,userCourse||0,performance.now());try{webkit.messageHandlers.routeReady.postMessage("ok");}catch(e){}},500);
  } else {
    appLog("❌ selectBusLine: drawing failed");
  }
}
