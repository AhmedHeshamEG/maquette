"""Blender opens a rigged, animated file Maquette wrote (glTF or FBX) and it plays: an armature with every joint, the
mesh skinned to it, an action, and bones that turn when it plays. Prints "MAQUETTE: rigged ..." and exits 1 otherwise.

Usage: blender -b --factory-startup --python-exit-code 1 --python Tools/check_rigged_import.py -- file.glb|file.fbx bones
"""

import sys

import bpy


def fail(message):
    print("MAQUETTE: FAILED: " + message)
    sys.exit(1)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    path, expected = args[0], int(args[1])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if path.lower().endswith(".fbx"):
        bpy.ops.import_scene.fbx(filepath=path)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not armatures:
        fail("no armature")
    armature = armatures[0]
    bones = len(armature.data.bones)
    if bones != expected:
        fail("%d bones, not %d" % (bones, expected))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    skinned = [m for m in meshes if any(mod.type == "ARMATURE" for mod in m.modifiers) and len(m.vertex_groups) > 0]
    if not skinned:
        fail("no mesh is skinned to the armature")
    # Blender 5 keeps an action's curves in layers; that the bones move between its ends is what counts.
    action = armature.animation_data.action if armature.animation_data else None
    if action is None:
        fail("no animation on the armature")
    start, end = action.frame_range
    scene = bpy.context.scene
    scene.frame_set(int(start))
    before = {b.name: b.matrix.copy() for b in armature.pose.bones}
    scene.frame_set(int(round(end)))
    moved = [b.name for b in armature.pose.bones if (b.matrix.to_quaternion().rotation_difference(before[b.name].to_quaternion()).angle > 1e-3)]
    if not moved:
        fail("no bone turns when it plays")
    print("MAQUETTE: rigged %s: %d bones, %d turn over frames %d-%d" % (path.rsplit(".", 1)[-1], bones, len(moved), start, end))


main()
