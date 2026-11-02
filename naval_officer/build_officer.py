"""
Chibi naval officer – procedural Blender model built from the reference sheet.
Run:  blender -b -P build_officer.py   (or: python build_officer.py with the bpy module)
Outputs (next to this script): naval_officer.blend, naval_officer.glb, render_*.png
Character faces -Y.  Character's right = -X, left (sword side) = +X.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

OUT = os.path.dirname(os.path.abspath(__file__))
RENDER = "--no-render" not in sys.argv

# ------------------------------------------------------------------ reset
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
col = scene.collection

# ------------------------------------------------------------------ materials
def mat(name, color, rough=0.55, metal=0.0, spec=0.3, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Specular IOR Level"].default_value = spec
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 1.0
    return m

def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)

M = {
    "skin":   mat("Skin",   srgb("#f9dcc8"), 0.7, spec=0.2),
    "blush":  mat("Blush",  srgb("#f2a7a0"), 0.8, spec=0.1),
    "hair":   mat("Hair",   srgb("#1c1c22"), 0.5, spec=0.3),
    "navy":   mat("Navy",   srgb("#1e2640"), 0.6),
    "navy_d": mat("NavyDark", srgb("#141a2c"), 0.5),
    "white":  mat("White",  srgb("#f2f2f0"), 0.6),
    "glove":  mat("Glove",  srgb("#fbfbfb"), 0.7),
    "gold":   mat("Gold",   srgb("#d4a73c"), 0.3, metal=0.9),
    "black":  mat("BlackGloss", srgb("#0d0d10"), 0.15, spec=0.6),
    "eye":    mat("Iris",   srgb("#2a2d36"), 0.2, spec=0.6),
    "eyehi":  mat("EyeHighlight", (1, 1, 1), 0.2, emit=(1, 1, 1)),
    "brow":   mat("Brow",   srgb("#1c1c22"), 0.6),
    "mouth":  mat("Mouth",  srgb("#b06a62"), 0.6),
    "sakura": mat("Sakura", srgb("#f5b8c8"), 0.5),
    "red":    mat("RibbonRed", srgb("#b52a2a"), 0.6),
    "blue":   mat("RibbonBlue", srgb("#7fa6d6"), 0.6),
}

# outline (inverted hull): black where front-facing, transparent where back-facing
OUTLINE = bpy.data.materials.new("Outline")
OUTLINE.use_nodes = True
nt = OUTLINE.node_tree
nt.nodes.clear()
o = nt.nodes.new("ShaderNodeOutputMaterial")
mix = nt.nodes.new("ShaderNodeMixShader")
geo = nt.nodes.new("ShaderNodeNewGeometry")
em = nt.nodes.new("ShaderNodeEmission"); em.inputs[0].default_value = (0.03, 0.03, 0.05, 1)
tr = nt.nodes.new("ShaderNodeBsdfTransparent")
lp = nt.nodes.new("ShaderNodeLightPath")
inv = nt.nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
mx = nt.nodes.new("ShaderNodeMath"); mx.operation = "MAXIMUM"
nt.links.new(lp.outputs["Is Camera Ray"], inv.inputs[1])
nt.links.new(geo.outputs["Backfacing"], mx.inputs[0])
nt.links.new(inv.outputs[0], mx.inputs[1])
nt.links.new(mx.outputs[0], mix.inputs[0])   # invisible to shadows / non-camera rays
nt.links.new(em.outputs[0], mix.inputs[1])
nt.links.new(tr.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], o.inputs[0])

# ------------------------------------------------------------------ helpers
def finish(obj, material, smooth=True, subsurf=0, outline=0.006):
    obj.data.materials.append(material)
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    if subsurf:
        m = obj.modifiers.new("Subsurf", "SUBSURF")
        m.levels = m.render_levels = subsurf
    if outline:
        obj.data.materials.append(OUTLINE)
        s = obj.modifiers.new("Outline", "SOLIDIFY")
        s.thickness = -outline
        s.offset = -1          # grow outward
        s.use_flip_normals = True
        s.use_rim = False
        s.material_offset = len(obj.data.materials) - 1
    return obj

def mesh_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob

def ellipsoid(name, loc, scale, material, rot=(0, 0, 0), seg=32, rings=16, **kw):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1)
    ob = mesh_obj(name, bm)
    ob.location, ob.scale, ob.rotation_euler = loc, scale, rot
    return finish(ob, material, **kw)

def loft(name, rings, material, seg=24, loc=(0, 0, 0), **kw):
    """rings: list of (z, rx, ry[, yoff]) -> closed tube with caps."""
    bm = bmesh.new()
    loops = []
    for r in rings:
        z, rx, ry = r[:3]; yo = r[3] if len(r) > 3 else 0
        loops.append([bm.verts.new((rx * math.cos(2 * math.pi * i / seg),
                                    ry * math.sin(2 * math.pi * i / seg) + yo, z))
                      for i in range(seg)])
    for a, b in zip(loops, loops[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(loops[0])))
    bm.faces.new(loops[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = mesh_obj(name, bm)
    ob.location = loc
    return finish(ob, material, **kw)

def tube(name, p1, p2, r1, r2, material, seg=20, **kw):
    """Tapered cylinder from p1 to p2."""
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    ob = loft(name, [(0, r1, r1), (d.length, r2, r2)], material, seg=seg, **kw)
    ob.location = p1
    ob.rotation_mode = "QUATERNION"
    ob.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    return ob

def ring(name, p1, p2, r, thick, material, **kw):
    """Short band (cuff stripe etc.) around axis p1->p2, centred on p1."""
    p1, p2 = Vector(p1), Vector(p2)
    d = (p2 - p1).normalized()
    return tube(name, p1 - d * thick / 2, p1 + d * thick / 2, r, r, material, seg=24, **kw)

def cord(name, pts, radius, material):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 3
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    for p, c in zip(sp.points, pts):
        p.co = (*c, 1)
    sp.use_endpoint_u = True
    sp.order_u = 3
    ob = bpy.data.objects.new(name, cu)
    col.objects.link(ob)
    cu.materials.append(material)
    return ob

def box(name, loc, size, material, rot=(0, 0, 0), bevel=0.01, **kw):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    ob = mesh_obj(name, bm)
    ob.location, ob.scale, ob.rotation_euler = loc, size, rot
    finish(ob, material, smooth=False, **kw)
    if bevel:
        b = ob.modifiers.new("Bevel", "BEVEL")
        b.width = bevel; b.segments = 3
        ob.modifiers.move(len(ob.modifiers) - 1, 0)
    return ob

# ------------------------------------------------------------------ proportions
HEAD_C = Vector((0, 0, 1.50))
HEAD_R = 0.40

def on_head(x, z, lift=0.0):
    """Point on the head sphere front surface at (x,z) + outward rotation."""
    dz = z - HEAD_C.z
    y = -math.sqrt(max(HEAD_R ** 2 - x ** 2 - dz ** 2, 0))
    n = Vector((x, y, dz)).normalized()
    loc = HEAD_C + n * (HEAD_R + lift)
    rot = Vector((0, -1, 0)).rotation_difference(n).to_euler()
    return loc, rot

# ------------------------------------------------------------------ head & face
ellipsoid("Head", HEAD_C, (HEAD_R, HEAD_R * 0.97, HEAD_R * 0.98), M["skin"], subsurf=1)
for s in (-1, 1):
    ellipsoid(f"Ear.{'L' if s>0 else 'R'}", HEAD_C + Vector((s * 0.39, 0.02, -0.04)),
              (0.05, 0.035, 0.075), M["skin"])

for s in (-1, 1):
    side = "L" if s > 0 else "R"
    loc, rot = on_head(s * 0.145, 1.47, 0.0)
    eye = ellipsoid(f"Eye.{side}", loc, (0.062, 0.02, 0.078), M["eye"], seg=24, rings=12)
    eye.rotation_euler = rot
    # upper lash line
    loc2, rot2 = on_head(s * 0.145, 1.548, 0.004)
    lash = box(f"Lash.{side}", loc2, (0.135, 0.012, 0.016), M["brow"], bevel=0.005, outline=0)
    lash.rotation_euler = (rot2.x, rot2.y, rot2.z + s * -0.0)
    lash.rotation_euler.y += s * 0.12
    # highlights
    for (dx, dz, r) in ((-0.022, 0.03, 0.017), (0.02, -0.03, 0.009)):
        l3, r3 = on_head(s * 0.145 + dx, 1.47 + dz, 0.022)
        ellipsoid(f"EyeHi.{side}", l3, (r, 0.006, r), M["eyehi"], seg=12, rings=6, outline=0)
    # stern brows (inner end lower)
    l4, r4 = on_head(s * 0.15, 1.625, 0.006)
    brow = box(f"Brow.{side}", l4, (0.12, 0.012, 0.018), M["brow"], bevel=0.005, outline=0)
    brow.rotation_euler = r4
    brow.rotation_euler.y += s * -0.22
    # blush
    l5, r5 = on_head(s * 0.23, 1.39, 0.0)
    b = ellipsoid(f"Blush.{side}", l5, (0.055, 0.008, 0.03), M["blush"], outline=0)
    b.rotation_euler = r5

l, r = on_head(0, 1.34, 0.0)
m = box("Mouth", l, (0.05, 0.01, 0.009), M["mouth"], bevel=0.004, outline=0); m.rotation_euler = r
l, r = on_head(0, 1.42, 0.0)
ellipsoid("Nose", l, (0.012, 0.01, 0.012), M["skin"], outline=0)

# ------------------------------------------------------------------ hair (bob)
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=1)
HR = 0.445
for v in bm.verts:
    x, y, z = v.co
    if z < 0.05:                      # straight sides below the equator
        h = math.hypot(x, y)
        if h > 1e-4:
            k = 1.0 + 0.03 * (-z)     # slight outward flare toward the tips
            v.co.x, v.co.y = x / h * k, y / h * k
    v.co *= HR
    v.co.y *= 0.97
# blunt bob cut
res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                             plane_co=(0, 0, -0.33), plane_no=(0, 0, 1), clear_inner=True)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary])
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
hair = mesh_obj("Hair", bm)
hair.location = HEAD_C + Vector((0, 0.015, 0))
# open the face
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
cutter = mesh_obj("FaceCut", bm)
cutter.location = HEAD_C + Vector((0, -0.45, -0.17))
cutter.scale = (0.62, 0.7, 0.62)
cutter.rotation_euler = (0, 0, 0)
bpy.context.view_layer.update()
# rounded top edge of the cut (bangs curve)
bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1)
cutter2 = mesh_obj("FaceCut2", bm)
cutter2.location = HEAD_C + Vector((0, -0.45, 0.10))
cutter2.scale = (0.31, 0.45, 0.10)
# open the cheeks/profile so the face reads from the side
side_cuts = []
for sx in (-1, 1):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    sc = mesh_obj(f"SideCut.{sx}", bm)
    sc.location = HEAD_C + Vector((sx * 0.36, -0.45, -0.12))
    sc.scale = (0.4, 0.62, 0.5)
    sc.rotation_euler = (math.radians(-12), 0, 0)
    side_cuts.append(sc)
for c in (cutter, cutter2, *side_cuts):
    bo = hair.modifiers.new("Bool", "BOOLEAN"); bo.object = c; bo.operation = "DIFFERENCE"; bo.solver = "EXACT"
    c.hide_render = True; c.hide_viewport = True
finish(hair, M["hair"], subsurf=0)
bv = hair.modifiers.new("Bevel", "BEVEL"); bv.width = 0.02; bv.segments = 3
# bang strands
for i, x in enumerate((-0.2, -0.1, 0.0, 0.1, 0.2)):
    loc, rot = on_head(x, 1.66 - abs(x) * 0.12, 0.035)
    st = ellipsoid(f"Bang.{i}", loc, (0.07, 0.04, 0.07), M["hair"], seg=16, rings=8)
    st.rotation_euler = rot

# ------------------------------------------------------------------ cap
CAP_Z = 1.80
loft("CapBand", [(CAP_Z - 0.06, 0.425, 0.425), (CAP_Z + 0.1, 0.44, 0.44)], M["navy"], seg=48)
crown = ellipsoid("CapCrown", (0, 0.03, CAP_Z + 0.16), (0.56, 0.54, 0.14), M["white"], seg=48)
loft("CapCrownSide", [(CAP_Z + 0.08, 0.44, 0.44), (CAP_Z + 0.17, 0.55, 0.53, 0.03)], M["white"], seg=48)
# visor: curved plate in front
bm = bmesh.new()
N = 24
inner, outer = [], []
for i in range(N + 1):
    a = math.radians(205 + 130 * i / N)
    t = math.sin(math.pi * i / N)
    ri, ro = 0.42, 0.42 + 0.17 * t ** 0.6 + 0.005
    inner.append(bm.verts.new((ri * math.cos(a), ri * math.sin(a), 0)))
    outer.append(bm.verts.new((ro * math.cos(a), ro * math.sin(a), -0.07 * t)))
for i in range(N):
    bm.faces.new((inner[i], inner[i + 1], outer[i + 1], outer[i]))
visor = mesh_obj("CapVisor", bm)
visor.location = (0, 0, CAP_Z - 0.05)
sol = visor.modifiers.new("Thick", "SOLIDIFY"); sol.thickness = 0.025
finish(visor, M["black"])
# chin strap + side buttons
cord("ChinStrap", [(-0.43, -0.05, CAP_Z - 0.03), (-0.3, -0.33, CAP_Z - 0.035),
                   (0, -0.44, CAP_Z - 0.04), (0.3, -0.33, CAP_Z - 0.035),
                   (0.43, -0.05, CAP_Z - 0.03)], 0.01, M["gold"])
for s in (-1, 1):
    ellipsoid("CapButton", (s * 0.425, -0.06, CAP_Z - 0.03), (0.022, 0.022, 0.022), M["gold"], outline=0.003)
# badge: gold wreath + sakura
bpy.ops.mesh.primitive_torus_add(major_radius=0.075, minor_radius=0.013, location=(0, -0.45, CAP_Z + 0.05),
                                 rotation=(math.pi / 2, 0, 0))
wreath = bpy.context.object; wreath.name = "BadgeWreath"; finish(wreath, M["gold"], outline=0.003)
for k in range(5):
    a = math.pi / 2 + 2 * math.pi * k / 5
    ellipsoid(f"Petal.{k}", (0.038 * math.cos(a), -0.47, CAP_Z + 0.05 + 0.038 * math.sin(a)),
              (0.03, 0.012, 0.03), M["sakura"], seg=16, rings=8, outline=0.003)
ellipsoid("PetalCenter", (0, -0.48, CAP_Z + 0.05), (0.014, 0.008, 0.014), M["gold"], outline=0)

# ------------------------------------------------------------------ body
tube("Neck", (0, 0, 1.08), (0, 0, 1.22), 0.07, 0.07, M["skin"])
loft("Collar", [(1.10, 0.115, 0.105), (1.20, 0.105, 0.1)], M["navy"], seg=24)
loft("Jacket", [
    (0.50, 0.29, 0.21), (0.58, 0.28, 0.205), (0.72, 0.265, 0.195), (0.88, 0.27, 0.19),
    (1.02, 0.29, 0.19), (1.10, 0.29, 0.185), (1.15, 0.22, 0.15), (1.17, 0.11, 0.10)],
    M["navy"], seg=32, subsurf=1)
# back vent pleats
for s in (-1, 1):
    box("BackPleat", (s * 0.04, 0.2, 0.62), (0.075, 0.025, 0.17), M["navy_d"], outline=0.004)
    ellipsoid("BackButton", (s * 0.08, 0.205, 0.75), (0.02, 0.012, 0.02), M["gold"], outline=0.003)
# front button rows
for s in (-1, 1):
    for z in (0.68, 0.79, 0.90, 1.01):
        ellipsoid("Button", (s * 0.085, -0.198, z), (0.02, 0.01, 0.02), M["gold"], seg=16, rings=8, outline=0.003)
# epaulettes
for s in (-1, 1):
    box(f"Epaulette.{'L' if s>0 else 'R'}", (s * 0.22, 0, 1.135), (0.14, 0.12, 0.03), M["gold"],
        rot=(0, s * -0.35, 0), bevel=0.012, outline=0.004)
# aiguillette on character's right (-X)
for sag, z0 in ((0.0, 0), (0.06, 1), (0.12, 2)):
    cord(f"Aiguillette.{z0}", [(-0.25, -0.12, 1.12), (-0.27, -0.2, 1.0 - sag),
                               (-0.2, -0.215, 0.92 - sag), (-0.14, -0.205, 1.02 - sag * 0.5),
                               (-0.11, -0.19, 1.1)], 0.011, M["gold"])
cord("AiguilletteTip", [(-0.2, -0.215, 0.92), (-0.21, -0.22, 0.82)], 0.012, M["gold"])
# medals on left chest (+X)
for i, (c, x) in enumerate(((M["red"], 0.13), (M["blue"], 0.19))):
    box(f"Ribbon.{i}", (x, -0.195, 1.04), (0.045, 0.02, 0.06), c, bevel=0.004, outline=0.003)
    st = bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.028, depth=0.012,
                                              location=(x, -0.205, 0.975), rotation=(math.pi / 2, 0, 0))
    star = bpy.context.object; star.name = f"Medal.{i}"
    bpy.ops.object.mode_set(mode="EDIT")
    bme = bmesh.from_edit_mesh(star.data)
    for v in bme.verts:
        ang = math.atan2(v.co.y, v.co.x)
        if round(ang / (math.pi / 4)) % 2:
            v.co.x *= 0.55; v.co.y *= 0.55
    bmesh.update_edit_mesh(star.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    finish(star, M["gold"], smooth=False, outline=0.003)

# ------------------------------------------------------------------ legs & shoes
for s in (-1, 1):
    side = "L" if s > 0 else "R"
    loft(f"Trouser.{side}", [(0.06, 0.105, 0.105), (0.3, 0.11, 0.11), (0.62, 0.125, 0.125)],
         M["white"], loc=(s * 0.125, 0, 0), seg=24)
    ellipsoid(f"Shoe.{side}", (s * 0.13, -0.045, 0.045), (0.105, 0.17, 0.065), M["black"])

# ------------------------------------------------------------------ arms (hands clasped in front)
for s in (-1, 1):
    side = "L" if s > 0 else "R"
    sh = Vector((s * 0.30, 0.0, 1.08))
    el = Vector((s * 0.36, -0.06, 0.83))
    wr = Vector((s * 0.09, -0.25, 0.80))
    ellipsoid(f"Shoulder.{side}", sh, (0.1, 0.1, 0.1), M["navy"])
    tube(f"UpperArm.{side}", sh, el, 0.095, 0.085, M["navy"])
    ellipsoid(f"Elbow.{side}", el, (0.085, 0.085, 0.085), M["navy"])
    tube(f"Forearm.{side}", el, wr, 0.085, 0.08, M["navy"])
    # gold cuff stripes
    d = (wr - el).normalized()
    for k, t in enumerate((0.05, 0.085, 0.12)):
        ring(f"Cuff.{side}.{k}", wr - d * t, wr, 0.087, 0.018, M["gold"], outline=0.003)
    ellipsoid(f"Glove.{side}", wr + d * 0.06 + Vector((0, -0.01, -0.01)),
              (0.075, 0.065, 0.06), M["glove"], rot=(0, 0, s * 0.4))
# fingers of the top hand wrapping over
for k in range(4):
    ellipsoid(f"Finger.{k}", (-0.04 + k * 0.03, -0.33, 0.79 - k * 0.003), (0.018, 0.03, 0.022), M["glove"],
              outline=0.003)

# ------------------------------------------------------------------ sword (character's left, +X)
top = Vector((0.34, -0.06, 0.66)); bot = Vector((0.40, 0.10, 0.06))
tube("Scabbard", top, bot, 0.025, 0.02, M["black"])
d = (bot - top).normalized()
tube("ScabbardTip", bot - d * 0.05, bot, 0.024, 0.02, M["gold"], outline=0.003)
tube("ScabbardMount", top + d * 0.08, top + d * 0.11, 0.029, 0.029, M["gold"], outline=0.003)
grip_top = top - d * 0.18
tube("Grip", top, grip_top, 0.022, 0.02, M["white"])
ellipsoid("Pommel", grip_top, (0.025, 0.025, 0.025), M["gold"], outline=0.003)
cord("Guard", [top + Vector((0, -0.03, 0)), top + Vector((0.01, -0.09, 0.06)),
               grip_top + Vector((0.0, -0.06, 0.0)), grip_top], 0.009, M["gold"])
tube("Sword Belt Strap", Vector((0.27, 0.05, 0.62)), top + d * 0.1, 0.008, 0.008, M["navy_d"])

# ------------------------------------------------------------------ scene, lights, cameras
bpy.ops.object.select_all(action="DESELECT")
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x = 700
scene.render.resolution_y = 900

world = bpy.data.worlds.new("World"); scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.9

def sun(name, rot, energy):
    l = bpy.data.lights.new(name, "SUN"); l.energy = energy; l.angle = math.radians(20)
    ob = bpy.data.objects.new(name, l); ob.rotation_euler = rot; col.objects.link(ob)
sun("Key", (math.radians(55), 0, math.radians(-25)), 3.0)
sun("Fill", (math.radians(60), 0, math.radians(160)), 1.2)

cam_data = bpy.data.cameras.new("Cam"); cam_data.type = "ORTHO"; cam_data.ortho_scale = 2.35
cam = bpy.data.objects.new("Camera", cam_data); col.objects.link(cam); scene.camera = cam
VIEWS = {
    "front": ((0, -10, 1.03), (math.pi / 2, 0, 0)),
    "side":  ((10, 0, 1.03), (math.pi / 2, 0, math.pi / 2)),
    "back":  ((0, 10, 1.03), (math.pi / 2, 0, math.pi)),
    "three_quarter": ((-6.5, -7.5, 1.9), (math.radians(85), 0, math.radians(-41))),
}
cam.location, cam.rotation_euler = VIEWS["front"]

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "naval_officer.blend"))
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "naval_officer.glb"), export_apply=True)

if RENDER:
    for name, (loc, rot) in VIEWS.items():
        cam.location, cam.rotation_euler = loc, rot
        scene.render.filepath = os.path.join(OUT, f"render_{name}.png")
        bpy.ops.render.render(write_still=True)
    cam.location, cam.rotation_euler = VIEWS["front"]
print("DONE")
