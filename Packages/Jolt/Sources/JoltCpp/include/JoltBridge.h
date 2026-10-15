// A small C face over Jolt Physics, so Swift can simulate without C++ interop. Units are SI: metres, kilograms,
// seconds, radians. Positions and rotations are world space; rotations are quaternions (x, y, z, w). Bodies and
// constraints are numbered in the order they were added, from 0. One world is single-threaded and deterministic: the
// same calls in the same order give the same result on every device.

#ifndef JOLT_BRIDGE_H
#define JOLT_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct JBWorld JBWorld;

typedef enum {
    JBShapeBox = 0,
    JBShapeSphere = 1,
    JBShapeCapsule = 2,
    JBShapeCylinder = 3,
    /// The convex hull of `points`.
    JBShapeConvexHull = 4,
    /// Triangles (`points` + `indices`); only for bodies that don't move.
    JBShapeMesh = 5,
    /// Several convex hulls glued into one body: `points` holds every hull's points one after another and
    /// `partCounts` how many each has.
    JBShapeCompound = 6
} JBShapeKind;

typedef enum {
    JBMotionStatic = 0,
    JBMotionKinematic = 1,
    JBMotionDynamic = 2
} JBMotion;

typedef struct {
    JBShapeKind shape;
    /// Box: half sizes. Capsule and cylinder: x = radius, y = half the height of the straight part (along local Y).
    /// Sphere: x = radius.
    float size[3];
    const float *points;
    int32_t pointCount;
    const uint32_t *indices;
    int32_t indexCount;
    const int32_t *partCounts;
    int32_t partCount;
    float position[3];
    float rotation[4];
    JBMotion motion;
    /// kg/m³; the mass is the density times the shape's real volume.
    float density;
    /// When > 0, the mass in kg (the inertia keeps the shape's distribution).
    float mass;
    float friction;
    float restitution;
    float linearDamping;
    float angularDamping;
    float linearVelocity[3];
    float angularVelocity[3];
    /// Bodies sharing a group other than 0 never collide with each other (a ragdoll's parts).
    uint32_t group;
    /// 0 keeps a body awake; settled bodies otherwise go to sleep.
    int32_t allowSleeping;
} JBBodyDesc;

typedef enum {
    JBJointFixed = 0,
    JBJointBall = 1,
    JBJointHinge = 2,
    JBJointSlider = 3,
    /// A spring (or a rope when `springFrequency` is 0) between two points.
    JBJointSpring = 4,
    /// A shoulder: a cone around `axis` and a twist range (ragdolls).
    JBJointSwingTwist = 5,
    /// Two hinges turning together at `ratio` (`gear1`, `gear2` are their constraint numbers).
    JBJointGear = 6
} JBJointKind;

typedef struct {
    JBJointKind kind;
    /// Body numbers; -1 is the world.
    int32_t bodyA;
    int32_t bodyB;
    float pointA[3];
    float pointB[3];
    /// The hinge's axis, the slider's direction, the twist axis.
    float axis[3];
    /// Perpendicular to `axis`.
    float normal[3];
    /// Radians for hinges and twists, metres for sliders and springs; min > max means no limit.
    float limitMin;
    float limitMax;
    /// 1 drives the joint at `motorSpeed` (rad/s or m/s) up to `motorStrength` (N·m or N).
    int32_t motor;
    float motorSpeed;
    float motorStrength;
    /// Springs: oscillations per second (0 = a stiff rope) and damping (0…1).
    float springFrequency;
    float springDamping;
    /// Swing-twist: the cone's half angle (radians).
    float swing;
    int32_t gear1;
    int32_t gear2;
    float ratio;
} JBJointDesc;

typedef struct {
    /// Vertices in world space.
    const float *vertices;
    int32_t vertexCount;
    const uint32_t *triangles;
    int32_t triangleCount;
    /// One per vertex: 0 holds the vertex where it is (pinned), else its mass in kg.
    const float *vertexMass;
    /// How much edges stretch (0 = not at all) and bend.
    float compliance;
    float bendCompliance;
    /// > 0 keeps a closed surface full (jelly).
    float pressure;
    float friction;
    float restitution;
    float linearDamping;
    int32_t iterations;
    float vertexRadius;
} JBSoftDesc;

/// A new, empty world. `maxBodies` bounds bodies and soft bodies together.
JBWorld *JBWorldCreate(int32_t maxBodies);
void JBWorldDestroy(JBWorld *world);
void JBWorldSetGravity(JBWorld *world, float x, float y, float z);

/// The body's number, or -1 when the shape couldn't be made (`JBWorldLastError`).
int32_t JBWorldAddBody(JBWorld *world, const JBBodyDesc *desc);
/// Takes a body out of the simulation (its number stays used).
void JBWorldRemoveBody(JBWorld *world, int32_t body);
int32_t JBWorldAddSoftBody(JBWorld *world, const JBSoftDesc *desc);
/// The constraint's number, or -1.
int32_t JBWorldAddJoint(JBWorld *world, const JBJointDesc *desc);

/// Advances by `dt` seconds in `substeps` collision steps.
void JBWorldStep(JBWorld *world, float dt, int32_t substeps);

/// Where a body is (its shape's origin) and how it's turned.
void JBBodyTransform(const JBWorld *world, int32_t body, float position[3], float rotation[4]);
void JBBodyVelocity(const JBWorld *world, int32_t body, float linear[3], float angular[3]);
/// The centre of mass in world space.
void JBBodyCenterOfMass(const JBWorld *world, int32_t body, float position[3]);
float JBBodyMass(const JBWorld *world, int32_t body);
int32_t JBBodyIsAwake(const JBWorld *world, int32_t body);
/// A force (N) at the centre of mass for the next step.
void JBBodyAddForce(JBWorld *world, int32_t body, const float force[3]);
void JBBodySetVelocity(JBWorld *world, int32_t body, const float linear[3], const float angular[3]);
/// Moves a kinematic body to arrive at this transform after `dt`.
void JBBodyMoveKinematic(JBWorld *world, int32_t body, const float position[3], const float rotation[4], float dt);
/// A soft body's vertices in world space (`out` holds 3 × the vertex count).
void JBSoftBodyVertices(const JBWorld *world, int32_t body, float *out);

/// Air moving at `wind` (m/s) pushes a soft body's faces for the next `dt` seconds (air at 1.2 kg/m³).
void JBSoftBodyApplyWind(JBWorld *world, int32_t body, const float wind[3], float dt);

/// What went wrong last, or an empty string.
const char *JBWorldLastError(const JBWorld *world);

#ifdef __cplusplus
}
#endif

#endif
