import Foundation

/// The actions vocabulary in one short page — served at GET /v2/actions, used by hmm-bridge's MCP server and the
/// lowey skill. Kept compact on purpose (it goes into AI context windows).
public enum ScriptReference {
    public static let text = """
    # Maquette Scene Script v3 — actions

    {"version": 3, "title": "...", "actions": [ {"do": ...}, ... ]}   (schemas/scene-script.v3.schema.json)
    The whole script is ONE undo step: a Proposal Hesham applies on the iPad (unless auto-apply is on). v2 scripts still
    work: they upgrade on the way in.

    Conventions
    - Units: metres, degrees, seconds. Y is up; the ground is y = 0. Say WHERE by relation, not coordinates.
    - Targets: an object name (case-insensitive), "Prefix*", an id, or a list. Names given earlier in the script work.
    - Times ("at"): seconds | "now" | "start" | "end" | {"word": "Enigma", "occurrence": 1, "edge": "start|end", "offset": -0.2} | {"marker": "name"}
      Prefer spoken words: shots stay synced if the voiceover moves.
    - Colours: "palette:N" (the project palette — prefer it) or "#RRGGBB".
    - Overlay "at" is frame space: [x, y] from -1 to 1 (0,0 = centre, y up).

    Build (Kit first: find_assets, then add by id; real sizes come with it)
    {"do":"add","asset":"kit.office-desk","name":"Desk","at":[0,0,0]}                 (an id, or words to search the Kit and library)
    {"do":"add","asset":"kit.room-lamproundtable","name":"Lamp","relation":"on","reference":"Desk","offset":[-0.4,0,0]}
    {"do":"place","target":"Lamp","relation":"on|beside_left|beside_right|in_front_of|behind|above|under|inside|facing|around|row|grid|scatter_in|stack",
     "reference":"Desk","offset":[x right, y up, z front],"radius":3,"spacing":0.2,"columns":3,"seed":1}
      Left/right as seen from the reference's front. Everything lands grounded and apart; the reply says where.
    {"do":"scaleTo","target":"Tree","meters":6,"axis":"height|width|depth|longest"}   {"do":"recolor","target":"Sofa","slot":2}
    {"do":"add","shape":"cube|sphere|cylinder|cone|plane|torus|ramp|group","name":"Wall","at":[0,0,-2],"size":[6,3,0.1],"color":"palette:1"}
    {"do":"text","text":"1941","at":[0,0.8,0],"size":0.2,"style":"blocky|rounded|bold|serif|mono"}
    {"do":"blob","likeness":"hesham|newton|einstein|turing|curie|darwin|tesla|lovelace|edison|sherlock|wizard","name":"Me","at":[0,0,0]}
    {"do":"blob","name":"Ada","facing":20,"label":"ADA","recipe":{"hat":"beret","hair":"bob","accessories":["glasses"],"prop":"gear"}}
    {"do":"particles","preset":"fire|sparks|smoke|dust|magic|rain|snow|confetti|embers|explosion","at":"Lamp","amount":1}
    {"do":"group","target":["A","B"],"name":"Set"}  {"do":"rename","target":"Cube","name":"Box"}  {"do":"remove","target":"Box"}
    {"do":"transform","target":"Paper","position":[0,1,0],"rotation":[0,45,0],"scale":2}   (edge cases only)

    Model (U6; faces by the way they face, edges by the axis they run along; one step each)
    {"do":"model","target":"Box","op":"pull","face":"top","distance":0.2}   {"do":"model","target":"Box","op":"loopCut","along":"x","cuts":2}
    {"do":"model","target":"Box","op":"smooth","levels":2}  ("subdivide" makes it real)   {"do":"model","target":"Box","op":"flat"}
    {"do":"model","target":"Tower","op":"bend","kind":"bend|twist|taper|bulge","amount":45,"axis":"y"}   (amount animates with "keys")
    {"do":"model","target":"Box","op":"cage","counts":[3,3,3]}  then  {"op":"cage","point":[2,2,2],"offset":[0.3,0,0]}   (counts: points per axis, 2–4; point: [i,j,k] from 0)
    {"do":"model","target":"Rock","op":"brush","brush":"grab|smooth|inflate","at":[0,1,0],"radius":0.3,"by":[0,0.2,0]}
    {"do":"model","target":"Sculpt","op":"cleanUp","faces":2000}   (even quads)   {"op":"knife","point":[0,0.5,0],"normal":[0,1,0]}
    {"do":"model","target":"Chair","op":"linkedCopy","offset":[1,0,0]}   {"op":"pivot","to":"base"}   {"op":"size","axis":"y","length":0.04}
    {"do":"model","target":"Block","op":"steps"}   (lists its modelling steps)   {"op":"step","step":1,"number":"diameter","value":0.008}   (H1: later steps replay)
    {"do":"sketch","name":"Side","plane":"xy","at":[0,0,0],"curves":[{"polyline":[[0,0],[0.4,0],[0.3,1]],"closed":true},{"circle":{"center":[0,0.5],"radius":0.1}}]}
        (plane: xy facing front, xz the ground, yz the side, or {origin, normal}; or "on":"Box","face":"top"; curves: line, rectangle, circle, arc [start, through, end], polyline, spline)
    {"do":"profile","target":"Sketch","region":0,"op":"revolve","axis":{"point":[0,0,0],"direction":[0,1,0]}}   ("pull" with "distance", negative cuts in; "sweep" with "path", "loft" with "through")
    {"do":"boolean","op":"subtract|union|intersect","target":"Body","with":["Arch front","Arch back"]}   (cut-outs: wheel arches, windows; the others are used up)

    Guests (G1): Room · Print · Study · Game (each tagged with its building part, so plans and IFC know a wall from a roof)
    {"do":"guest","op":"roof","kind":"gable|hip|shed|flat","over":"Walls","pitch":30}   ("outline":[[x,y,z],…] for any shape)
    {"do":"guest","op":"column|person|label|terrain","at":[2,0,1],"text":"Kitchen","yaw":30,"width":20,"hills":1}
    {"do":"guest","op":"beam","from":[0,2.7,0],"to":[4,2.7,0]}   {"do":"guest","op":"railing","path":[[0,0,0],[3,0,0]]}
    {"do":"guest","op":"print","piece":"jar|bolt|nut","screw":"M6"}   {"do":"guest","op":"hole","target":"Box","screw":"M3","kind":"clearance|counterbore|tapped|threaded|insert","face":"top"}
    {"do":"guest","op":"split","target":"Helmet","axis":"y","at":0.12,"pegs":true}   {"do":"guest","op":"hollow|orient","target":"Bust","wall":0.002}
    {"do":"guest","op":"engrave|emboss","target":"Lid","text":"GIULIA","face":"top","size":0.006}   {"do":"guest","op":"scale","target":"Box","size":0.1,"axis":"x"}
    {"do":"guest","op":"explode","target":"Gearbox"}   (again: back together)   {"do":"character","op":"new","start":"mannequin"}
    {"do":"guest","op":"greybox","piece":"floor|tile|wall|doorway|window|ramp|stairs|block|pillar","at":[4,0,0]}   {"do":"guest","op":"freeze","targets":"Level*"}

    Review notes (U8): pins on a spot, carried in the file, answered in place
    {"do":"note","text":"Taller back?","on":"Chair"}   ("at":[x,y,z] for a spot; on a thing it follows the thing)
    {"do":"note","op":"list"}   {"do":"note","op":"reply","note":1,"text":"Done"}   {"do":"note","op":"resolve|reopen|delete","note":1}

    Film (F1; "camera" defaults to the shot camera)
    {"do":"light","type":"panel|bulb|spot|sun","name":"Window","at":[2,2,2],"size":[1.2,0.8],"aim":"Hero"}   (panel = a soft panel)
    {"do":"lighting","recipe":"three-point|golden-hour|moonlit|neon|key-warm-world-cool|noir-single-source|golden-rim|monitor-glow|studio-soft","subject":"Hero"}
    {"do":"film","op":"lens","camera":"Shot","mm":35,"sensor":"fullFrame|super35|apsC|microFourThirds|super16|phone|largeFormat|imax","aperture":2.8}
    {"do":"film","op":"frame","shape":"16:9|2.39:1|9:16|4:5|1:1"}   (the Director view, Frame shot and every export)
    {"do":"film","op":"focus","on":"Hero","at":{"word":"look"}}   (follows it; a later one pulls focus; "on":null = by distance)
    {"do":"film","op":"rig","kind":"none|dolly|crane|orbit|handheld","travel":2,"lift":1.5,"swing":30,"arm":3,"shake":0.4,"keys":{"lift":[[0,0],[3,2]]}}
    {"do":"film","op":"air","haze":0.4,"godRays":0.6,"color":"#FFD9A0"}   {"op":"environment","turn":40}  (an HDRI comes over add_media)   {"op":"shots"}

    Texture (U7; each a layer or a setting, one step each)
    {"do":"paint","target":"Crate","op":"material","material":"oak|steel|gold|brick|stone|fabric|…","scale":0.2}   {"op":"color","color":"#B5512E"}
    {"do":"paint","target":"Crate","op":"wear","kind":"dirt|edges","amount":0.6}   {"op":"mirror","axis":"x"}   {"op":"size","pixels":1024}
    {"do":"paint","target":"Crate","op":"decal","picture":"media/logo.png","at":[0,0.5,0.5],"size":0.3}   {"op":"faces","at":[0,1,0],"color":"#22AA44"}
    {"do":"paint","target":"Crate","op":"layers"}   (lists them)   {"op":"mask","layer":2}   {"op":"seams","edges":[[[x,y,z],[x,y,z]],…]}
    {"do":"paint","target":"Light copy","op":"bakeNormals","from":"Sculpt"}   {"do":"paint","target":"Fox","op":"fur","length":0.03,"style":"shells|cards"}

    Physics (P1; real things move when the timeline plays, from the scene's physics start; each one step)
    {"do":"physics","op":"real","target":"Crate","material":"wood|steel|aluminium|stone|concrete|glass|ice|plastic|rubber|foam|cardboard|cloth|jelly","motion":"falls|stays|follows"}   {"op":"unreal","target":"Crate"}
    {"do":"physics","op":"real","target":"Ball","mass":2,"bounce":0.8,"speed":[2,0,0],"breaks":true}   {"op":"real","target":"Flag","material":"cloth","hangs":true}
    {"do":"physics","op":"scene","gravity":"earth|moon|mars|jupiter|none","wind":{"speed":6,"heading":90},"ground":true,"start":0.5}
    {"do":"physics","op":"joint","kind":"hinge|slider|ball|glue|spring|rope|gear","first":"Door","second":"Frame","anchor":[0,1,0],"axis":[0,1,0],"limits":[0,110],"motor":45}
    {"do":"physics","op":"joint","kind":"gear","first":"Wheel A","gears":["hingeA","hingeB"],"ratio":2}   {"op":"unjoin","id":"hingeA"}
    {"do":"physics","op":"force","kind":"fan|pull|whirl","at":[0,1,2],"aim":[0,0,-1],"strength":8,"reach":3}
    {"do":"physics","op":"fluid","kind":"pour|splash|smoke|fire","at":[0,0.4,0],"amount":0.3,"duration":3,"box":[1,1,1]}
    {"do":"physics","op":"keep"}   (the run becomes keys)   {"op":"settle","target":"Rock"}   {"op":"stand","target":"Tower"}   (says whether it stands)
    {"do":"physics","op":"sun","place":"Rome","date":"2026-06-21","hour":15,"north":0,"study":[7,19]}   {"op":"sun","latitude":45.1,"longitude":7.7,"utcOffset":2}   {"op":"sun","off":true}

    Shoot and light
    {"do":"frameShot","subject":"Hesham","shotType":"extremeWide|wide|full|medium|closeUp|extremeCloseUp|overTheShoulder|twoShot|insert",
     "composition":"center|leftThird|rightThird|lowAngle|highAngle","lens":85,"other":"Ada","side":"left|right","camera":"Shot 2","at":{"word":"Nobody"}}
    {"do":"cameraMove","camera":"Shot 2","move":"pushIn|pullOut|punchIn|snapZoom|orbit|dolly|truck|crane|whipPan|shake|reveal","subject":"Paper","at":{"word":"message"},"duration":2,"strength":1}
    {"do":"cut","camera":"Room cam","at":{"word":"people"},"transition":"cut|fade|dipToBlack|wipe|zoomThrough","duration":0.6}
    {"do":"lighting","recipe":"key-warm-world-cool|noir-single-source|golden-rim|monitor-glow|moonlit|studio-soft","subject":"Hesham","intensity":1,"warmth":0.3}
    {"do":"look","look":"ink|comic|sketch|painterly|watercolour|gouache|paperman|animeCel|clay|cleanProduct|lowPoly|pixel","mood":"day|goldenHour|dusk|night|space|studio|darkStudio","perObject":{"Robot":"sketch"},"fog":40,"sceneOnly":true}
    {"do":"look","ground":"desert|grass|snow|rock|sand|pavement|waterEdge|roomFloor|plain","finish":{"misregistration":true,"boil":0.4,"benDay":0.6,"texture":"none|paper|collage|film|newsprint|riso|canvas","textureStrength":0.7}}

    Animate (say the intent; the app picks the animation)
    {"do":"intent","target":"Hesham","what":"enter|exit|emphasise|react|walk_to|look_at|talk|idle","how":"surprised","to":"Door","at":{"word":"Nobody"},"frameRate":"twos"}
    {"do":"preset","target":"Screen*","preset":"popIn|popOut|grow|shrink|bounce|wiggle|float|spin|shake|pulse|fadeIn|fadeOut|slideIn|dropIn|typewriter",
     "at":{"word":"Nobody"},"duration":0.5,"strength":1,"stagger":0.08,"order":"selection|leftToRight|rightToLeft|wave"}
    {"do":"expression","target":"Me","name":"neutral|happy|laugh|smug|surprised|shocked|scared|sad|angry|sleepy|wink|thinking","at":{"word":"what"}}
    {"do":"clip","character":"Me","clip":"Idle|Walk|Run|Talk|Wave|Point|Type|Nod|Shrug|Celebrate","at":0,"loop":true}
    {"do":"lipSync","character":"Me","words":"optional phrase"}
    {"do":"keys","target":"Paper","property":"scale","keys":[{"t":0,"value":[1,1,1]},{"t":{"word":"huge"},"value":[8,8,8],"easing":"easeInOut"}]}

    Motion (A1; each one step)
    {"do":"motion","op":"path","target":"Car","points":[[0,0,0],[3,0,2],[6,0,0]],"times":[0,1.2,2],"at":1}   ("speed":2 or "duration":3 instead of times; "facesTheWay":false, "banks":false)
    {"do":"motion","op":"follow","target":"Bee","path":"Flight line","duration":4,"loop":true}   (a drawn line)
    {"do":"motion","op":"lookAt","target":"Ada","at":"Ball"}   {"op":"lookAt","target":"Ada","at":"Door","from":3}   (from 3 s on)   {"at":"nothing"}
    {"do":"motion","op":"pickUp","target":"Cup","by":"Ada","joint":"rightHand","at":2}   (a hand-off when someone holds it)   {"op":"putDown","target":"Cup","at":5}   {"op":"letGo","target":"Cup"}
    {"do":"motion","op":"evenSpeed","target":"Car"}   {"op":"timing","target":"Car","duration":3}   {"op":"front","target":"Car","quarterTurns":1}
    {"do":"set","target":"Paper","property":"color|opacity|emissiveIntensity|stepping|accent|airborne|smear","value":"#F2E8D5","at":2}
    Easings: linear, easeIn, easeOut, easeInOut, backOut, bounce, elastic, step.

    Story
    {"do":"overlay","shape":"title|label|arrow|highlight|cross|question|exclamation|check|circle|rectangle|triangle|star","text":"1941","at":[0,0.55],"size":1.5,"follow":"Paper"}
    {"do":"flipbook","fx":"speedLines|impactBurst|sweatDrop|sparkle|smear","anchor":"Robot","at":{"word":"boom"},"until":3.2,"color":"#FFFFFF"}
    {"do":"effect","kind":"flash|shake|speedLines|zoomBlur|glitch|impact|focusLines|kirbyDots","at":{"word":"Nobody"},"duration":0.4,"strength":1}
    {"do":"effect","kind":"focusLines","at":2,"target":"Hero"}   (impact, focusLines and kirbyDots aim at a thing, or "center":[0.5,0.4] from the top left)
    {"do":"transcript","text":"Two plus two equals four.","from":0.2,"to":3.6}   (or "words":[{"w":"Two","t":0.2,"e":0.4}]: known timings)
    {"do":"marker","name":"enigma","at":{"word":"Enigma"}}   {"do":"captions","style":"punchy|subtitle|pill|outline","position":"bottom"}
    {"do":"length","seconds":12,"fps":30}

    Good shots: one idea per shot; one subject, the biggest, brightest or most contrasty thing; build only what the lens
    sees; light the subject warm against a cool world; move the camera on a word; hold still between moves; ≤ 7 things.
    """
}
