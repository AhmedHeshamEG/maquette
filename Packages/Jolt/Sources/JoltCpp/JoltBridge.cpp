// The C face over Jolt Physics (see include/JoltBridge.h).

#include "JoltBridge.h"

#include <Jolt/Jolt.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayerInterfaceTable.h>
#include <Jolt/Physics/Collision/BroadPhase/ObjectVsBroadPhaseLayerFilterTable.h>
#include <Jolt/Physics/Collision/GroupFilter.h>
#include <Jolt/Physics/Collision/ObjectLayerPairFilterTable.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/StaticCompoundShape.h>
#include <Jolt/Physics/Constraints/DistanceConstraint.h>
#include <Jolt/Physics/Constraints/FixedConstraint.h>
#include <Jolt/Physics/Constraints/GearConstraint.h>
#include <Jolt/Physics/Constraints/HingeConstraint.h>
#include <Jolt/Physics/Constraints/PointConstraint.h>
#include <Jolt/Physics/Constraints/SliderConstraint.h>
#include <Jolt/Physics/Constraints/SwingTwistConstraint.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/SoftBody/SoftBodyCreationSettings.h>
#include <Jolt/Physics/SoftBody/SoftBodyMotionProperties.h>
#include <Jolt/Physics/SoftBody/SoftBodySharedSettings.h>
#include <Jolt/RegisterTypes.h>

#include <mutex>
#include <string>
#include <vector>

using namespace JPH;

namespace {

constexpr ObjectLayer kStill = 0;
constexpr ObjectLayer kMoving = 1;

void registerOnce() {
    static std::once_flag once;
    std::call_once(once, [] {
        RegisterDefaultAllocator();
        Factory::sInstance = new Factory();
        RegisterTypes();
    });
}

/// Bodies sharing a group other than 0 skip each other.
class SameGroupFilter final : public GroupFilter {
public:
    bool CanCollide(const CollisionGroup &a, const CollisionGroup &b) const override {
        return a.GetGroupID() == CollisionGroup::cInvalidGroup || a.GetGroupID() != b.GetGroupID();
    }
};

Vec3 vec(const float v[3]) { return Vec3(v[0], v[1], v[2]); }

Quat quat(const float q[4]) {
    Quat r(q[0], q[1], q[2], q[3]);
    float length = r.Length();
    return length > 1.0e-6f ? r / length : Quat::sIdentity();
}

void put(Vec3Arg v, float out[3]) {
    out[0] = v.GetX();
    out[1] = v.GetY();
    out[2] = v.GetZ();
}

} // namespace

struct JBWorld {
    ObjectLayerPairFilterTable pairs{2};
    BroadPhaseLayerInterfaceTable layers{2, 2};
    ObjectVsBroadPhaseLayerFilterTable *objectVsBroadPhase = nullptr;
    PhysicsSystem system;
    TempAllocatorImpl temp{32 * 1024 * 1024};
    JobSystemSingleThreaded jobs{cMaxPhysicsJobs};
    Ref<SameGroupFilter> groups = new SameGroupFilter();
    std::vector<BodyID> bodies;
    std::vector<Ref<Constraint>> joints;
    std::string error;

    explicit JBWorld(int32_t maxBodies) {
        pairs.EnableCollision(kMoving, kStill);
        pairs.EnableCollision(kMoving, kMoving);
        layers.MapObjectToBroadPhaseLayer(kStill, BroadPhaseLayer(0));
        layers.MapObjectToBroadPhaseLayer(kMoving, BroadPhaseLayer(1));
        objectVsBroadPhase = new ObjectVsBroadPhaseLayerFilterTable(layers, 2, pairs, 2);
        uint count = uint(maxBodies > 16 ? maxBodies : 16);
        system.Init(count, 0, count * 4, count * 4, layers, *objectVsBroadPhase, pairs);
        PhysicsSettings settings = system.GetPhysicsSettings();
        settings.mDeterministicSimulation = true;
        system.SetPhysicsSettings(settings);
    }

    ~JBWorld() {
        for (Ref<Constraint> &joint : joints) {
            if (joint != nullptr) system.RemoveConstraint(joint);
        }
        BodyInterface &bodyInterface = system.GetBodyInterface();
        for (BodyID id : bodies) {
            if (id.IsInvalid()) continue;
            if (bodyInterface.IsAdded(id)) bodyInterface.RemoveBody(id);
            bodyInterface.DestroyBody(id);
        }
        delete objectVsBroadPhase;
    }

    BodyID body(int32_t index) const {
        return index >= 0 && size_t(index) < bodies.size() ? bodies[size_t(index)] : BodyID();
    }
};

namespace {

ShapeRefC makeShape(JBWorld *world, const JBBodyDesc &desc) {
    float density = desc.density > 0 ? desc.density : 1000.0f;
    ShapeSettings::ShapeResult result;
    switch (desc.shape) {
    case JBShapeBox: {
        Vec3 half(std::max(desc.size[0], 0.002f), std::max(desc.size[1], 0.002f), std::max(desc.size[2], 0.002f));
        float radius = std::min(0.02f, 0.5f * half.ReduceMin());
        BoxShapeSettings settings(half, radius);
        settings.SetDensity(density);
        result = settings.Create();
        break;
    }
    case JBShapeSphere: {
        SphereShapeSettings settings(std::max(desc.size[0], 0.002f));
        settings.SetDensity(density);
        result = settings.Create();
        break;
    }
    case JBShapeCapsule: {
        CapsuleShapeSettings settings(std::max(desc.size[1], 0.001f), std::max(desc.size[0], 0.002f));
        settings.SetDensity(density);
        result = settings.Create();
        break;
    }
    case JBShapeCylinder: {
        float radius = std::max(desc.size[0], 0.002f);
        float half = std::max(desc.size[1], 0.002f);
        CylinderShapeSettings settings(half, radius, std::min(0.02f, 0.5f * std::min(radius, half)));
        settings.SetDensity(density);
        result = settings.Create();
        break;
    }
    case JBShapeConvexHull: {
        Array<Vec3> points;
        points.reserve(size_t(desc.pointCount));
        for (int32_t i = 0; i < desc.pointCount; ++i) points.push_back(vec(desc.points + 3 * i));
        ConvexHullShapeSettings settings(points, 0.01f);
        settings.SetDensity(density);
        result = settings.Create();
        break;
    }
    case JBShapeMesh: {
        VertexList vertices;
        vertices.reserve(size_t(desc.pointCount));
        for (int32_t i = 0; i < desc.pointCount; ++i) {
            vertices.push_back(Float3(desc.points[3 * i], desc.points[3 * i + 1], desc.points[3 * i + 2]));
        }
        IndexedTriangleList triangles;
        for (int32_t i = 0; i + 2 < desc.indexCount; i += 3) {
            triangles.push_back(IndexedTriangle(desc.indices[i], desc.indices[i + 1], desc.indices[i + 2]));
        }
        MeshShapeSettings settings(vertices, triangles);
        result = settings.Create();
        break;
    }
    case JBShapeCompound: {
        StaticCompoundShapeSettings compound;
        int32_t start = 0;
        for (int32_t part = 0; part < desc.partCount; ++part) {
            Array<Vec3> points;
            for (int32_t i = 0; i < desc.partCounts[part] && start + i < desc.pointCount; ++i) {
                points.push_back(vec(desc.points + 3 * (start + i)));
            }
            start += desc.partCounts[part];
            Ref<ConvexHullShapeSettings> hull = new ConvexHullShapeSettings(points, 0.005f);
            hull->SetDensity(density);
            compound.AddShape(Vec3::sZero(), Quat::sIdentity(), hull);
        }
        result = compound.Create();
        break;
    }
    }
    if (result.HasError()) {
        world->error = std::string(result.GetError().c_str());
        return nullptr;
    }
    return result.Get();
}

} // namespace

extern "C" {

JBWorld *JBWorldCreate(int32_t maxBodies) {
    registerOnce();
    return new JBWorld(maxBodies);
}

void JBWorldDestroy(JBWorld *world) { delete world; }

void JBWorldSetGravity(JBWorld *world, float x, float y, float z) { world->system.SetGravity(Vec3(x, y, z)); }

int32_t JBWorldAddBody(JBWorld *world, const JBBodyDesc *desc) {
    ShapeRefC shape = makeShape(world, *desc);
    if (shape == nullptr) return -1;
    EMotionType motion = desc->motion == JBMotionDynamic ? EMotionType::Dynamic
        : desc->motion == JBMotionKinematic ? EMotionType::Kinematic : EMotionType::Static;
    if (desc->shape == JBShapeMesh && motion == EMotionType::Dynamic) motion = EMotionType::Kinematic;
    BodyCreationSettings settings(shape, RVec3(vec(desc->position)), quat(desc->rotation), motion,
                                  motion == EMotionType::Static ? kStill : kMoving);
    settings.mFriction = desc->friction;
    settings.mRestitution = desc->restitution;
    settings.mLinearDamping = desc->linearDamping;
    settings.mAngularDamping = desc->angularDamping;
    settings.mLinearVelocity = vec(desc->linearVelocity);
    settings.mAngularVelocity = vec(desc->angularVelocity);
    settings.mAllowSleeping = desc->allowSleeping != 0;
    settings.mMaxAngularVelocity = 60.0f;
    if (desc->mass > 0 && motion == EMotionType::Dynamic) {
        settings.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
        settings.mMassPropertiesOverride.mMass = desc->mass;
    }
    if (desc->group != 0) settings.mCollisionGroup = CollisionGroup(world->groups, desc->group, 0);
    BodyID id = world->system.GetBodyInterface().CreateAndAddBody(
        settings, motion == EMotionType::Static ? EActivation::DontActivate : EActivation::Activate);
    if (id.IsInvalid()) {
        world->error = "Too many bodies";
        return -1;
    }
    world->bodies.push_back(id);
    return int32_t(world->bodies.size() - 1);
}

void JBWorldRemoveBody(JBWorld *world, int32_t body) {
    BodyID id = world->body(body);
    if (id.IsInvalid()) return;
    BodyInterface &bodyInterface = world->system.GetBodyInterface();
    if (bodyInterface.IsAdded(id)) bodyInterface.RemoveBody(id);
}

int32_t JBWorldAddSoftBody(JBWorld *world, const JBSoftDesc *desc) {
    Ref<SoftBodySharedSettings> shared = new SoftBodySharedSettings();
    for (int32_t i = 0; i < desc->vertexCount; ++i) {
        float mass = desc->vertexMass != nullptr ? desc->vertexMass[i] : 1.0f;
        SoftBodySharedSettings::Vertex vertex(Float3(desc->vertices[3 * i], desc->vertices[3 * i + 1], desc->vertices[3 * i + 2]));
        vertex.mInvMass = mass > 0 ? 1.0f / mass : 0.0f;
        shared->mVertices.push_back(vertex);
    }
    for (int32_t i = 0; i + 2 < desc->triangleCount * 3; i += 3) {
        SoftBodySharedSettings::Face face(desc->triangles[i], desc->triangles[i + 1], desc->triangles[i + 2]);
        if (!face.IsDegenerate()) shared->AddFace(face);
    }
    SoftBodySharedSettings::VertexAttributes attributes(desc->compliance, desc->compliance, desc->bendCompliance);
    shared->CreateConstraints(&attributes, 1, SoftBodySharedSettings::EBendType::Distance);
    shared->Optimize();
    SoftBodyCreationSettings settings(shared, RVec3::sZero(), Quat::sIdentity(), kMoving);
    settings.mPressure = desc->pressure;
    settings.mVertexRadius = desc->vertexRadius;
    settings.mFriction = desc->friction;
    settings.mRestitution = desc->restitution;
    settings.mLinearDamping = desc->linearDamping;
    settings.mNumIterations = uint32(desc->iterations > 0 ? desc->iterations : 5);
    settings.mAllowSleeping = false;
    BodyID id = world->system.GetBodyInterface().CreateAndAddSoftBody(settings, EActivation::Activate);
    if (id.IsInvalid()) {
        world->error = "Too many bodies";
        return -1;
    }
    world->bodies.push_back(id);
    return int32_t(world->bodies.size() - 1);
}

int32_t JBWorldAddJoint(JBWorld *world, const JBJointDesc *desc) {
    BodyID a = world->body(desc->bodyA);
    BodyID b = world->body(desc->bodyB);
    if (a.IsInvalid() && b.IsInvalid()) {
        world->error = "A joint needs a body";
        return -1;
    }
    Vec3 axis = vec(desc->axis);
    axis = axis.Length() > 1.0e-6f ? axis.Normalized() : Vec3::sAxisY();
    Vec3 normal = vec(desc->normal);
    normal = (normal - axis * normal.Dot(axis));
    normal = normal.Length() > 1.0e-6f ? normal.Normalized() : axis.GetNormalizedPerpendicular();
    bool limited = desc->limitMin <= desc->limitMax;
    Ref<TwoBodyConstraintSettings> settings;
    switch (desc->kind) {
    case JBJointFixed: {
        Ref<FixedConstraintSettings> fixed = new FixedConstraintSettings();
        fixed->mSpace = EConstraintSpace::WorldSpace;
        fixed->mAutoDetectPoint = true;
        settings = fixed;
        break;
    }
    case JBJointBall: {
        Ref<PointConstraintSettings> ball = new PointConstraintSettings();
        ball->mSpace = EConstraintSpace::WorldSpace;
        ball->mPoint1 = RVec3(vec(desc->pointA));
        ball->mPoint2 = RVec3(vec(desc->pointA));
        settings = ball;
        break;
    }
    case JBJointHinge: {
        Ref<HingeConstraintSettings> hinge = new HingeConstraintSettings();
        hinge->mSpace = EConstraintSpace::WorldSpace;
        hinge->mPoint1 = hinge->mPoint2 = RVec3(vec(desc->pointA));
        hinge->mHingeAxis1 = hinge->mHingeAxis2 = axis;
        hinge->mNormalAxis1 = hinge->mNormalAxis2 = normal;
        if (limited) {
            hinge->mLimitsMin = std::max(desc->limitMin, -JPH_PI);
            hinge->mLimitsMax = std::min(desc->limitMax, JPH_PI);
        }
        hinge->mMotorSettings.SetTorqueLimit(desc->motorStrength > 0 ? desc->motorStrength : 1.0e4f);
        settings = hinge;
        break;
    }
    case JBJointSlider: {
        Ref<SliderConstraintSettings> slider = new SliderConstraintSettings();
        slider->mSpace = EConstraintSpace::WorldSpace;
        slider->mPoint1 = slider->mPoint2 = RVec3(vec(desc->pointA));
        slider->mSliderAxis1 = slider->mSliderAxis2 = axis;
        slider->mNormalAxis1 = slider->mNormalAxis2 = normal;
        if (limited) {
            slider->mLimitsMin = std::min(desc->limitMin, 0.0f);
            slider->mLimitsMax = std::max(desc->limitMax, 0.0f);
        }
        slider->mMotorSettings.SetForceLimit(desc->motorStrength > 0 ? desc->motorStrength : 1.0e4f);
        settings = slider;
        break;
    }
    case JBJointSpring: {
        Ref<DistanceConstraintSettings> spring = new DistanceConstraintSettings();
        spring->mSpace = EConstraintSpace::WorldSpace;
        spring->mPoint1 = RVec3(vec(desc->pointA));
        spring->mPoint2 = RVec3(vec(desc->pointB));
        if (limited) {
            spring->mMinDistance = desc->limitMin;
            spring->mMaxDistance = desc->limitMax;
        }
        spring->mLimitsSpringSettings.mFrequency = desc->springFrequency;
        spring->mLimitsSpringSettings.mDamping = desc->springDamping;
        settings = spring;
        break;
    }
    case JBJointSwingTwist: {
        Ref<SwingTwistConstraintSettings> twist = new SwingTwistConstraintSettings();
        twist->mSpace = EConstraintSpace::WorldSpace;
        twist->mPosition1 = twist->mPosition2 = RVec3(vec(desc->pointA));
        twist->mTwistAxis1 = twist->mTwistAxis2 = axis;
        twist->mPlaneAxis1 = twist->mPlaneAxis2 = normal;
        twist->mNormalHalfConeAngle = desc->swing;
        twist->mPlaneHalfConeAngle = desc->swing;
        twist->mTwistMinAngle = limited ? desc->limitMin : -0.3f;
        twist->mTwistMaxAngle = limited ? desc->limitMax : 0.3f;
        settings = twist;
        break;
    }
    case JBJointGear: {
        bool valid = desc->gear1 >= 0 && size_t(desc->gear1) < world->joints.size() && desc->gear2 >= 0 &&
            size_t(desc->gear2) < world->joints.size();
        if (!valid) {
            world->error = "A gear needs two hinges";
            return -1;
        }
        Ref<GearConstraintSettings> gear = new GearConstraintSettings();
        gear->mSpace = EConstraintSpace::WorldSpace;
        gear->mHingeAxis1 = axis;
        gear->mHingeAxis2 = vec(desc->normal).Length() > 1.0e-6f ? vec(desc->normal).Normalized() : axis;
        gear->mRatio = desc->ratio != 0 ? desc->ratio : 1.0f;
        settings = gear;
        break;
    }
    }
    TwoBodyConstraint *constraint = world->system.GetBodyInterface().CreateConstraint(settings, a, b);
    if (constraint == nullptr) {
        world->error = "The joint couldn't be made";
        return -1;
    }
    if (desc->kind == JBJointGear) {
        static_cast<GearConstraint *>(constraint)->SetConstraints(world->joints[size_t(desc->gear1)], world->joints[size_t(desc->gear2)]);
    }
    if (desc->motor != 0) {
        if (desc->kind == JBJointHinge) {
            auto *hinge = static_cast<HingeConstraint *>(constraint);
            hinge->SetMotorState(EMotorState::Velocity);
            hinge->SetTargetAngularVelocity(desc->motorSpeed);
        } else if (desc->kind == JBJointSlider) {
            auto *slider = static_cast<SliderConstraint *>(constraint);
            slider->SetMotorState(EMotorState::Velocity);
            slider->SetTargetVelocity(desc->motorSpeed);
        }
    }
    world->system.AddConstraint(constraint);
    world->system.GetBodyInterface().ActivateConstraint(constraint);
    world->joints.push_back(constraint);
    return int32_t(world->joints.size() - 1);
}

void JBWorldStep(JBWorld *world, float dt, int32_t substeps) {
    world->system.Update(dt, substeps > 0 ? substeps : 1, &world->temp, &world->jobs);
}

void JBBodyTransform(const JBWorld *world, int32_t body, float position[3], float rotation[4]) {
    BodyID id = world->body(body);
    if (id.IsInvalid()) return;
    RVec3 p;
    Quat q;
    world->system.GetBodyInterfaceNoLock().GetPositionAndRotation(id, p, q);
    put(Vec3(p), position);
    rotation[0] = q.GetX();
    rotation[1] = q.GetY();
    rotation[2] = q.GetZ();
    rotation[3] = q.GetW();
}

void JBBodyVelocity(const JBWorld *world, int32_t body, float linear[3], float angular[3]) {
    BodyID id = world->body(body);
    if (id.IsInvalid()) return;
    Vec3 l;
    Vec3 a;
    world->system.GetBodyInterfaceNoLock().GetLinearAndAngularVelocity(id, l, a);
    put(l, linear);
    put(a, angular);
}

void JBBodyCenterOfMass(const JBWorld *world, int32_t body, float position[3]) {
    BodyID id = world->body(body);
    if (id.IsInvalid()) return;
    put(Vec3(world->system.GetBodyInterfaceNoLock().GetCenterOfMassPosition(id)), position);
}

float JBBodyMass(const JBWorld *world, int32_t body) {
    BodyID id = world->body(body);
    if (id.IsInvalid()) return 0;
    BodyLockRead lock(world->system.GetBodyLockInterfaceNoLock(), id);
    if (!lock.Succeeded()) return 0;
    const Body &found = lock.GetBody();
    if (!found.IsDynamic()) return 0;
    float inverse = found.GetMotionProperties()->GetInverseMass();
    return inverse > 0 ? 1.0f / inverse : 0;
}

int32_t JBBodyIsAwake(const JBWorld *world, int32_t body) {
    BodyID id = world->body(body);
    return id.IsInvalid() ? 0 : (world->system.GetBodyInterfaceNoLock().IsActive(id) ? 1 : 0);
}

void JBBodyAddForce(JBWorld *world, int32_t body, const float force[3]) {
    BodyID id = world->body(body);
    if (!id.IsInvalid()) world->system.GetBodyInterface().AddForce(id, vec(force));
}

void JBBodySetVelocity(JBWorld *world, int32_t body, const float linear[3], const float angular[3]) {
    BodyID id = world->body(body);
    if (!id.IsInvalid()) world->system.GetBodyInterface().SetLinearAndAngularVelocity(id, vec(linear), vec(angular));
}

void JBBodyMoveKinematic(JBWorld *world, int32_t body, const float position[3], const float rotation[4], float dt) {
    BodyID id = world->body(body);
    if (!id.IsInvalid()) world->system.GetBodyInterface().MoveKinematic(id, RVec3(vec(position)), quat(rotation), dt);
}

void JBSoftBodyVertices(const JBWorld *world, int32_t body, float *out) {
    BodyID id = world->body(body);
    if (id.IsInvalid()) return;
    BodyLockRead lock(world->system.GetBodyLockInterfaceNoLock(), id);
    if (!lock.Succeeded()) return;
    const Body &found = lock.GetBody();
    if (!found.IsSoftBody()) return;
    const auto *motion = static_cast<const SoftBodyMotionProperties *>(found.GetMotionProperties());
    RMat44 transform = found.GetCenterOfMassTransform();
    size_t index = 0;
    for (const SoftBodyVertex &vertex : motion->GetVertices()) {
        put(Vec3(transform * vertex.mPosition), out + 3 * index);
        ++index;
    }
}

void JBSoftBodyApplyWind(JBWorld *world, int32_t body, const float wind[3], float dt) {
    BodyID id = world->body(body);
    if (id.IsInvalid()) return;
    BodyLockWrite lock(world->system.GetBodyLockInterface(), id);
    if (!lock.Succeeded()) return;
    Body &found = lock.GetBody();
    if (!found.IsSoftBody()) return;
    auto *motion = static_cast<SoftBodyMotionProperties *>(found.GetMotionProperties());
    Array<SoftBodyVertex> &vertices = motion->GetVertices();
    Mat44 toLocal = found.GetCenterOfMassTransform().InversedRotationTranslation().GetRotation();
    Vec3 air = toLocal.Multiply3x3(vec(wind));
    for (const SoftBodySharedSettings::Face &face : motion->GetSettings()->mFaces) {
        SoftBodyVertex &a = vertices[face.mVertex[0]];
        SoftBodyVertex &b = vertices[face.mVertex[1]];
        SoftBodyVertex &c = vertices[face.mVertex[2]];
        Vec3 cross = (b.mPosition - a.mPosition).Cross(c.mPosition - a.mPosition);
        float twiceArea = cross.Length();
        if (twiceArea < 1.0e-9f) continue;
        Vec3 normal = cross / twiceArea;
        Vec3 relative = air - (a.mVelocity + b.mVelocity + c.mVelocity) / 3.0f;
        float across = relative.Dot(normal);
        Vec3 force = normal * (0.5f * 1.2f * 0.5f * twiceArea * across * std::abs(across));
        for (SoftBodyVertex *vertex : {&a, &b, &c}) {
            vertex->mVelocity += force * (vertex->mInvMass * dt / 3.0f);
        }
    }
    world->system.GetBodyInterfaceNoLock().ActivateBody(id);
}

const char *JBWorldLastError(const JBWorld *world) { return world->error.c_str(); }

} // extern "C"
