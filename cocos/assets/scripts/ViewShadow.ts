import { Camera, Canvas, Node, UITransform, Vec2, Vec3 } from 'cc';

const cameras = new WeakMap<Node, { camera: Camera; canvas: Node }>();
const light = new Vec3(), localLight = new Vec3();

/** Cast from a light beside the viewer onto the object's own receiving plane. */
export function viewShadowOffset(space: Node, point: Vec3, elevation: number, out = new Vec2()) {
    let view = cameras.get(space);
    if (!view) {
        for (let parent: Node | null = space; parent; parent = parent.parent) {
            const canvas = parent.getComponent(Canvas);
            if (canvas?.cameraComponent) { view = { camera: canvas.cameraComponent, canvas: parent }; cameras.set(space, view); break; }
        }
    }
    if (!view) return out.set(elevation * .65, -elevation * .75);
    const eye = view.camera.node.worldPosition, distance = Math.max(1, Math.abs(eye.z - view.canvas.worldPosition.z));
    light.set(eye.x - distance * .65, eye.y + distance * .55, eye.z);
    space.getComponent(UITransform)!.convertToNodeSpaceAR(light, localLight);
    const height = Math.max(0, elevation) * Math.abs(space.worldScale.x);
    const ratio = height / Math.max(height + 1, localLight.z - height);
    return out.set((point.x - localLight.x) * ratio, (point.y - localLight.y) * ratio);
}
