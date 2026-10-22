"""Writes schemas/scene-script.v3.schema.json: every Scene Script v3 verb with its fields.

The shared definitions (commands, times, targets…) come from the v2 schema. Run it after adding a verb;
`--check` (CI) fails when the file on disk is out of date. A Core test checks the verbs match the compiler's.
"""
import copy
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "schemas"
old = json.load(open(ROOT / "scene-script.schema.json", encoding="utf-8"))
defs = copy.deepcopy(old['$defs'])

def ref(name):
    return {"$ref": f"#/$defs/{name}"}

s = {"type": "string"}
n = {"type": "number"}
b = {"type": "boolean"}
tgt = ref("target")
time = ref("time")
point = ref("point")
color = ref("color")
v3 = ref("vec3")

relations = ["on", "beside_left", "beside_right", "in_front_of", "behind", "above", "under", "inside", "facing",
             "around", "row", "grid", "scatter_in", "stack"]
shot_types = ["extremeWide", "wide", "full", "medium", "closeUp", "extremeCloseUp", "overTheShoulder", "twoShot", "insert"]
compositions = ["center", "leftThird", "rightThird", "lowAngle", "highAngle"]
recipes = ["three-point", "golden-hour", "moonlit", "neon", "key-warm-world-cool", "noir-single-source", "golden-rim", "monitor-glow",
           "studio-soft"]
intents = ["enter", "exit", "emphasise", "react", "walk_to", "look_at", "talk", "idle"]
looks = ["ink", "comic", "sketch", "painterly", "watercolour", "gouache", "paperman", "animeCel", "clay", "cleanProduct", "lowPoly",
         "lowpoly", "pixel"]
fx = ["speedLines", "impactBurst", "sweatDrop", "sparkle", "smear"]
expressions = ["neutral", "happy", "laugh", "smug", "surprised", "shocked", "scared", "sad", "angry", "sleepy", "wink", "thinking"]
presets = ["popIn", "popOut", "grow", "shrink", "bounce", "wiggle", "float", "spin", "shake", "pulse", "fadeIn", "fadeOut",
           "slideIn", "dropIn", "typewriter"]
moves = ["pushIn", "pullOut", "punchIn", "snapZoom", "orbit", "dolly", "truck", "crane", "whipPan", "shake", "reveal"]
clips = ["Idle", "Walk", "Run", "Talk", "Wave", "Point", "Type", "Nod", "Shrug", "Celebrate"]

verbs = {
    "add": ("A Kit/library model (\"asset\": an id like kit.office-desk, or words), a shape, or a group; optionally placed by relation.",
            {"asset": s, "shape": {"enum": ["cube", "sphere", "cylinder", "cone", "plane", "torus", "ramp", "group"]}, "name": s,
             "at": point, "size": {"anyOf": [n, v3]}, "color": color, "rotation": v3, "glow": n, "parent": tgt, "onGround": b,
             "look": {"enum": looks}, "relation": {"enum": relations}, "reference": tgt, "offset": v3}, []),
    "place": ("Place by relation (grounded, apart from what's there; left/right as seen from the reference's front).",
              {"target": tgt, "relation": {"enum": relations}, "reference": tgt, "offset": v3, "radius": n, "spacing": n,
               "columns": n, "seed": n}, ["target", "relation"]),
    "scaleTo": ("Real-world size in metres.", {"target": tgt, "meters": n, "axis": {"enum": ["height", "width", "depth", "longest"]}},
                ["target", "meters"]),
    "recolor": ("Tint with a palette slot.", {"target": tgt, "slot": n}, ["target", "slot"]),
    "remove": ("Delete.", {"target": tgt}, ["target"]),
    "group": ("Group under a new parent.", {"target": tgt, "name": s}, ["target"]),
    "rename": ("Rename.", {"target": tgt, "name": s}, ["target", "name"]),
    "transform": ("Absolute transform (edge cases).", {"target": tgt, "position": v3, "rotation": v3, "scale": {"anyOf": [n, v3]},
                                                       "relative": b, "at": time, "easing": s}, ["target"]),
    "text": ("3D words; `font` names a font file brought into the project (fonts/…).",
             {"text": s, "name": s, "at": point, "size": n, "style": s, "font": s, "color": color, "glow": n}, ["text"]),
    "blob": ("A Blob character (a likeness or a recipe).", {"name": s, "likeness": s, "at": point, "facing": n, "label": s,
                                                           "recipe": {"type": "object"}}, []),
    "character": ("A humanoid puppet from a recipe; or, with \"op\", K1's character maker: \"new\" from a start (person, fourLegs, "
                  "wings, blob, nothing), \"add\" a part to a character or any thing (paired parts mirrored unless symmetric is false), "
                  "\"style\" (another of the part's set), \"remove\", \"assign\" (a thing becomes a part, or the drawing of a face "
                  "state), \"state\" (bend a face state: open, wide, round, smile, lift, tilt, close; or reset), \"proportion\" (by a "
                  "factor or to metres), \"say\" (lip sync a typed line), \"rig\". Changes to parts rig it again in the same step.",
                  {"name": s, "at": point, "facing": n, "recipe": {"type": "object"},
                   "op": {"enum": ["new", "add", "style", "remove", "assign", "state", "proportion", "say", "rig"]},
                   "start": {"enum": ["person", "fourLegs", "wings", "blob", "nothing"]}, "target": tgt, "character": tgt,
                   "part": {"enum": ["head", "eye", "brow", "mouth", "nose", "ear", "hair", "body", "arm", "leg", "tail", "wing", "extra"]},
                   "style": s, "symmetric": b, "side": {"enum": ["left", "right", "middle"]}, "state": s,
                   "bend": {"type": "object", "properties": {k: n for k in ["open", "wide", "round", "smile", "lift", "tilt", "close"]}},
                   "reset": b, "measure": {"enum": ["height", "head", "body", "waist", "arms", "legs"]}, "by": n, "to": n,
                   "line": s, "language": s}, []),
    "particles": ("An emitter.", {"preset": s, "name": s, "at": point, "amount": n, "time": time}, ["preset"]),
    "light": ("A light: a bulb (point), a spot, a sun, or a soft panel (a rectangle, \"size\" in metres) aimed at a thing.",
              {"type": {"enum": ["point", "bulb", "spot", "sun", "panel"]}, "name": s, "at": point, "color": color, "intensity": n,
               "range": n, "size": {"type": "array", "items": n}, "aim": point}, []),
    "camera": ("A camera.", {"name": s, "from": point, "lookAt": point, "focalLength": n, "fov": n, "aperture": n, "active": b}, []),
    "frameShot": ("The camera solver: shot type and composition on a subject (a new camera when \"camera\" doesn't exist).",
                  {"subject": tgt, "shotType": {"enum": shot_types}, "composition": {"enum": compositions}, "lens": n, "other": tgt,
                   "side": {"enum": ["left", "right"]}, "camera": s, "at": time, "aspect": n, "active": b}, ["subject"]),
    "lighting": ("A lighting recipe placed for the shot camera (replaces the recipe's earlier lamps).",
                 {"recipe": {"enum": recipes}, "subject": tgt, "intensity": n, "warmth": n}, ["recipe"]),
    "look": ("The Look, mood and post; per-object Looks.", {"look": {"enum": looks}, "mood": s, "post": s, "shading": s,
                                                            "fog": {"anyOf": [b, n]}, "palette": {"type": "array", "items": color},
                                                            "bloom": n, "grain": n, "sceneOnly": b,
                                                            "ground": {"enum": ["plain", "desert", "grass", "snow", "rock", "sand", "pavement",
                                                                                "waterEdge", "roomFloor"]},
                                                            "finish": {"type": "object", "properties": {
                                                                "misregistration": b, "boil": n, "benDay": n, "textureStrength": n,
                                                                "texture": {"enum": ["none", "paper", "collage", "film", "newsprint", "riso", "canvas"]}}},
                                                            "perObject": {"type": "object", "additionalProperties": {"enum": looks}}}, []),
    "intent": ("Say what it should do; the app picks the animation.", {"target": tgt, "what": {"enum": intents},
               "how": {"enum": expressions}, "to": {"anyOf": [tgt, v3]}, "at": time, "on_word": s, "duration": n, "strength": n,
               "frameRate": {"enum": ["ones", "twos", "threes", "fours"]}, "words": s}, ["target", "what"]),
    "preset": ("A motion preset.", {"target": tgt, "preset": {"enum": presets}, "at": time, "duration": n, "strength": n,
                                    "stagger": n, "order": {"enum": ["selection", "leftToRight", "rightToLeft", "wave"]}, "from": point},
               ["target", "preset"]),
    "keys": ("Keyframes.", {"target": tgt, "property": s, "keys": {"type": "array", "items": {"type": "object", "required": ["value"],
             "properties": {"t": time, "at": time, "value": {}, "easing": s}}}}, ["target", "property", "keys"]),
    "set": ("A property (keyed when \"at\" is given).", {"target": tgt, "property": s, "value": {}, "at": time}, ["target", "property"]),
    "expression": ("A face, from a moment on.", {"target": tgt, "character": tgt, "name": {"enum": expressions}, "at": time}, ["name"]),
    "clip": ("A built-in clip.", {"character": tgt, "target": tgt, "clip": {"enum": clips}, "at": time, "duration": n, "loop": b,
                                  "from": s}, ["clip"]),
    "transcript": ("Words with known timings on a voiceover clip (a script, a laptop TTS).", {"clip": s, "text": s, "from": n, "to": n,
                   "language": s, "words": {"type": "array", "items": {"type": "object", "required": ["w", "t"],
                   "properties": {"w": s, "t": n, "e": n}}}}, []),
    "lipSync": ("Mouth shapes from the transcript.", {"character": tgt, "target": tgt, "words": s}, []),
    "cameraMove": ("A camera move.", {"camera": tgt, "move": {"enum": moves}, "subject": {"anyOf": [tgt, v3]}, "at": time,
                                      "duration": n, "strength": n}, ["move"]),
    "cut": ("Cut to a camera.", {"camera": tgt, "at": time, "transition": {"enum": ["cut", "fade", "dipToBlack", "wipe", "zoomThrough"]},
                                 "duration": n}, ["camera"]),
    "overlay": ("A 2D overlay in frame space.", {"shape": s, "name": s, "text": s, "at": {"type": "array", "items": n}, "size": n,
                                                 "follow": tgt, "color": color}, ["shape"]),
    "flipbook": ("Drawn FX from the library.", {"fx": {"enum": fx}, "anchor": {"anyOf": [tgt, v3]}, "at": time, "until": time,
                                               "color": color, "frames": n, "name": s}, ["fx"]),
    "effect": ("A screen effect; impact, focusLines and kirbyDots aim at a thing (target) or a point (center, 0…1 from the top left).",
               {"kind": {"enum": ["flash", "shake", "speedLines", "zoomBlur", "glitch", "impact", "focusLines", "kirbyDots"]}, "at": time,
                "duration": n, "strength": n, "color": color, "target": tgt, "center": {"type": "array", "items": n}}, ["kind"]),
    "marker": ("A timeline marker.", {"name": s, "at": time}, ["at"]),
    "captions": ("Captions on/off and style.", {"enabled": b, "style": s, "position": s}, []),
    "array": ("Copies in a line or ring.", {"target": tgt, "count": n, "step": v3, "radius": n, "faceCenter": b, "name": s}, ["target"]),
    "scatter": ("Copies scattered.", {"target": tgt, "count": n, "radius": n, "at": point, "name": s}, ["target"]),
    "length": ("The timeline's length.", {"seconds": n, "fps": n}, []),
    "model": ("U6's modelling set on one thing: smooth, subdivide, smoothAngle, flat, bend, cage, brush, pull, loopCut, knife, "
              "fillHoles, mergeByDistance, cleanUp, linkedCopy, unlink, pivot, size; H1's steps (list) and step (change one).",
              {"target": tgt, "op": {"enum": ["smooth", "subdivide", "smoothAngle", "flat", "bend", "cage", "brush", "pull", "loopCut",
                                              "knife", "fillHoles", "mergeByDistance", "cleanUp", "linkedCopy", "unlink", "pivot", "size",
                                              "steps", "step"]},
               "levels": n, "degrees": n, "on": b, "kind": {"enum": ["bend", "twist", "taper", "bulge"]}, "amount": n,
               "axis": {"enum": ["x", "y", "z"]}, "counts": {"type": "array", "items": n}, "point": {"anyOf": [v3, {"type": "array"}]},
               "offset": v3, "remove": b, "brush": {"enum": ["grab", "smooth", "inflate"]}, "at": point, "radius": n,
               "strength": n, "by": v3, "mirror": b, "face": {"enum": ["top", "bottom", "front", "back", "left", "right"]},
               "distance": n, "along": {"enum": ["x", "y", "z"]}, "cuts": n, "normal": v3, "faces": n, "quadsOnly": b,
               "to": {"enum": ["middle", "base"]}, "length": n,
               "step": n, "number": {"anyOf": [s, n]}, "value": n}, ["target", "op"]),
    "profile": ("A sketch region made into a solid: pulled out of its plane (a negative distance cuts into the thing it was "
                "drawn on), swept along a path, revolved around an axis or lofted through others.",
                {"target": tgt, "region": n, "op": {"enum": ["pull", "sweep", "revolve", "loft"]}, "distance": n,
                 "path": {"type": "array", "items": v3}, "closed": b,
                 "axis": {"type": "object", "properties": {"point": v3, "direction": v3}}, "degrees": n, "through": tgt},
                ["target", "op"]),
    "sketch": ("Construction curves on a plane (xy facing front, xz the ground, yz the side, or an origin and a normal) or on "
               "the face of a thing; closed curves make the areas profile uses. Points are metres on the plane.",
               {"name": s, "plane": {"anyOf": [{"enum": ["xy", "xz", "yz"]},
                                              {"type": "object", "properties": {"origin": v3, "normal": v3}}]},
                "at": point, "on": tgt, "face": {"enum": ["top", "bottom", "front", "back", "left", "right"]},
                "curves": {"type": "array", "items": {"type": "object"}}}, ["curves"]),
    "boolean": ("Combines shapes into the target (it keeps its name, look and place; the others are used up): subtract cuts "
                "wheel arches and windows, union joins, intersect keeps the overlap.",
                {"op": {"enum": ["union", "subtract", "intersect"]}, "target": tgt, "with": tgt}, ["op", "target", "with"]),
    "paint": ("U7's texturing on one thing: a fill layer of a colour, a material or wear; a decal; whole faces; the layers; "
              "a mask; mirrored strokes; the texture's size; hand-marked seams; normals baked from a detailed copy; fur.",
              {"target": tgt, "op": {"enum": ["color", "material", "wear", "decal", "faces", "layers", "mask", "mirror", "size", "seams",
                                              "bakeNormals", "fur"]},
               "color": s, "material": s, "scale": n, "kind": {"enum": ["dirt", "edges"]}, "amount": n, "picture": s, "at": point,
               "facing": v3, "size": n, "opacity": n, "layer": n, "on": b, "axis": {"enum": ["x", "y", "z"]},
               "pixels": {"enum": [512, 1024, 2048, 4096]}, "edges": {"type": "array", "items": {"type": "array", "items": v3}},
               "from": tgt, "length": n, "density": n, "style": {"enum": ["shells", "cards"]}, "droop": n}, ["target", "op"]),
    "physics": ("P1's physics: make things real (a material in words, how they move, their numbers), the scene's gravity, "
                "wind, ground and start, joints and mechanisms, forces (fan, pull, whirl) and fluids (pour, splash, smoke, "
                "fire), Keep it (the run becomes keys), Settle, does it stand, and the real sun of a place and date.",
                {"op": {"enum": ["real", "unreal", "scene", "joint", "unjoin", "force", "fluid", "keep", "settle", "stand", "sun"]},
                 "target": tgt, "material": {"enum": ["wood", "steel", "aluminium", "stone", "concrete", "glass", "ice", "plastic",
                                                      "rubber", "foam", "cardboard", "cloth", "jelly"]},
                 "motion": {"enum": ["falls", "stays", "follows"]}, "mass": n, "friction": n, "bounce": n, "speed": v3, "spin": v3,
                 "breaks": b, "stiffness": n, "hangs": b,
                 "gravity": {"anyOf": [{"enum": ["earth", "moon", "mars", "jupiter", "none"]}, n]},
                 "wind": {"type": "object", "properties": {"speed": n, "heading": n, "gusts": n}}, "ground": b, "start": n,
                 "kind": {"enum": ["hinge", "slider", "ball", "glue", "spring", "rope", "gear", "fan", "pull", "whirl", "pour", "splash",
                                   "smoke", "fire"]},
                 "id": s, "first": tgt, "second": tgt, "anchor": point, "to": point, "axis": v3, "limits": {"type": "array", "items": n},
                 "motor": n, "springiness": n, "length": n, "gears": {"type": "array", "items": s}, "ratio": n,
                 "at": point, "aim": v3, "reach": n, "box": v3, "amount": n, "duration": n, "color": s, "width": n,
                 "place": s, "latitude": n, "longitude": n, "utcOffset": n, "date": s, "hour": n, "north": n,
                 "study": {"anyOf": [{"type": "array", "items": n}, b]}, "off": b}, ["op"]),
    "motion": ("A1's motion: a path the thing follows at the line's own timing (\"times\" from the first point, else a "
               "steady \"speed\" or a \"duration\"), facing the way it goes and leaning into turns (characters stay upright); "
               "following a drawn line; looking at a thing (a character turns its head; \"from\" switches the look at a "
               "moment); picking up and handing off (\"by\" a thing or a skeleton's \"joint\"), putting down, letting go; "
               "even speed, the timing of a whole motion, and turning its front.",
               {"op": {"enum": ["path", "follow", "lookAt", "pickUp", "putDown", "letGo", "evenSpeed", "timing", "front"]},
                "target": tgt, "points": {"type": "array", "items": v3}, "times": {"type": "array", "items": n}, "speed": n,
                "duration": n, "at": {"anyOf": [time, tgt]}, "from": time, "facesTheWay": b, "banks": b, "upright": b,
                "path": tgt, "line": tgt, "loop": b, "by": tgt, "joint": s, "quarterTurns": n}, ["target", "op"]),
    "film": ("F1's film tools: a lens in millimetres on a camera body; the picture's shape; focus that follows a thing (a "
             "later one pulls focus); a rig (dolly, crane, orbit, handheld) with its moves keyed; haze and god rays; turning "
             "the HDRI; and the shots as a storyboard would list them.",
             {"op": {"enum": ["lens", "frame", "focus", "rig", "air", "environment", "shots"]}, "camera": tgt, "mm": n,
              "sensor": {"enum": ["fullFrame", "super35", "apsC", "microFourThirds", "super16", "phone", "largeFormat", "imax"]},
              "aperture": n, "shape": {"enum": ["16:9", "2.39:1", "9:16", "4:5", "1:1"]}, "on": {"anyOf": [tgt, {"type": "null"}]},
              "at": time, "kind": {"enum": ["none", "dolly", "crane", "orbit", "handheld"]}, "travel": n, "lift": n, "swing": n,
              "arm": n, "shake": n, "keys": {"type": "object"}, "haze": n, "godRays": n, "color": color, "turn": n, "exposure": n,
              "off": b}, ["op"]),
    "design": ("D1's motion design: an SVG logo stood up as solids (one a colour); copies of a thing in a grid, a circle, a "
               "line or along a path, moved by effects (random, delay, push) through fields (everywhere, near a point, a "
               "ripple); links that let a thing's motion or a sound (loudness, bass, beat) drive another thing; a morph into "
               "another thing's shape; letters that animate; and the loop check, which can close the loop.",
               {"op": {"enum": ["logo", "clone", "effect", "link", "morph", "letters", "loop"]}, "target": tgt, "name": s,
                "svg": s, "file": s, "width": n, "depth": n, "at": time,
                "layout": {"enum": ["grid", "circle", "line", "path"]}, "count": n, "columns": n, "rows": n, "layers": n,
                "spacing": {"anyOf": [v3, n]}, "radius": n, "facesOut": b, "step": v3, "path": tgt, "along": b,
                "kind": {"enum": ["random", "delay", "push"]}, "move": v3, "turn": v3, "grow": n, "delay": n,
                "field": {"enum": ["everywhere", "sphere", "ripple"]}, "centre": v3, "speed": n, "every": n, "clear": b,
                "channel": {"enum": ["moveX", "moveY", "moveZ", "turnX", "turnY", "turnZ", "size", "glow", "opacity", "effect",
                                     "morph", "reveal"]},
                "from": tgt, "fromChannel": {"enum": ["moveX", "moveY", "moveZ", "turnX", "turnY", "turnZ", "size"]},
                "sound": s, "feature": {"enum": ["loudness", "bass", "beat"]}, "amount": n, "into": tgt, "duration": n,
                "preset": {"enum": ["flyIn", "bounce", "cascade", "pop", "spin", "typewriter", "wave", "none"]},
                "order": {"enum": ["forward", "backward", "middle", "random"]}, "stagger": n, "length": n, "close": b,
                "off": b}, ["op"]),
    "guest": ("G1's guest kits. Room: roofs over walls or an outline, columns, beams, railings, scale people, terrain, a name "
              "lying on the floor. Print: the best way up, a split with pegs, hollowing with drain holes, engraving or embossing "
              "text, ISO screw holes (M2-M10: clearance, counterbored, for a tap, threaded, a heat-set insert), a jar with a "
              "screw-on lid, bolts and nuts, scale to size. Study: explode a group (and back). Game: greybox pieces on a metre "
              "grid, freeze transforms.",
              {"op": {"enum": ["roof", "column", "beam", "railing", "person", "terrain", "label", "explode", "orient", "split",
                               "hollow", "engrave", "emboss", "hole", "print", "scale", "greybox", "freeze"]},
               "target": tgt, "targets": tgt, "name": s, "kind": s, "outline": {"type": "array", "items": v3}, "over": tgt,
               "pitch": n, "at": {"anyOf": [v3, n, tgt]}, "height": n, "shape": {"enum": ["round", "square"]}, "from": v3, "to": v3,
               "path": {"type": "array", "items": v3}, "yaw": n, "width": n, "depth": n, "hills": n, "seed": n, "text": s,
               "axis": {"enum": ["x", "y", "z"]}, "pegs": b, "tolerance": n, "wall": n, "drain": n,
               "face": {"enum": ["top", "bottom", "front", "back", "left", "right"]}, "size": n,
               "screw": {"enum": ["M2", "M2.5", "M3", "M4", "M5", "M6", "M8", "M10"]},
               "piece": {"enum": ["jar", "bolt", "nut", "floor", "tile", "wall", "doorway", "window", "ramp", "stairs", "block",
                                  "pillar"]}}, ["op"]),
    "note": ("U8's review notes: a pin on a thing (it follows the thing) or at a point, carried in the file and answered in "
             "place; list them, reply, resolve, reopen or delete one by its number or id.",
             {"op": {"enum": ["add", "list", "reply", "resolve", "reopen", "delete"]}, "text": s, "on": tgt, "at": v3,
              "note": {"anyOf": [n, s]}, "author": s, "time": n}, []),
    "command":("A raw EditCommand.", {"command": ref("command")}, ["command"]),
}

action = {
    "type": "object",
    "required": ["do"],
    "properties": {"do": {"enum": sorted(verbs)}},
    "allOf": [],
    "additionalProperties": True,
}
for verb, (description, props, required) in sorted(verbs.items()):
    then = {"description": description, "properties": props}
    if required:
        then["required"] = required
    action["allOf"].append({"if": {"properties": {"do": {"const": verb}}}, "then": then})
defs["action"] = action

schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://github.com/AhmedHeshamEG/3D-lowey/schemas/scene-script.v3.schema.json",
    "title": "3D-lowey Scene Script v3",
    "description": "Actions that speak relations, not coordinates: add from the Kit, place by relation (grounded, apart), "
                   "frame shots, light by recipe, animate by intent. One script = one Proposal = one undo step. v1/v2 scripts "
                   "upgrade on the way in. Short reference: GET /v2/actions (LoweyCore ScriptReference).",
    "type": "object",
    "required": ["title"],
    "properties": {
        "version": {"enum": [1, 2, 3]},
        "title": s,
        "commands": {"type": "array", "items": ref("command")},
        "actions": {"type": "array", "items": ref("action")},
    },
    "$defs": defs,
}
text = json.dumps(schema, indent=2, ensure_ascii=False) + "\n"
target = ROOT / "scene-script.v3.schema.json"
if "--check" in sys.argv:
    if target.read_text(encoding="utf-8") != text:
        sys.exit("schemas/scene-script.v3.schema.json is out of date: run python Tools/gen-script-schema.py")
    print(f"Scene Script v3 schema is up to date ({len(verbs)} verbs).")
else:
    target.write_text(text, encoding="utf-8", newline="\n")
    print(f"Wrote {target.name} ({len(verbs)} verbs).")
