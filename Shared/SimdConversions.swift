import simd

extension simd_quatd {
    init(_ quaternion: Quaternion) {
        self.init(ix: quaternion.x, iy: quaternion.y, iz: quaternion.z, r: quaternion.w)
    }
}

extension Quaternion {
    init(_ quaternion: simd_quatd) {
        self.init(x: quaternion.imag.x, y: quaternion.imag.y, z: quaternion.imag.z, w: quaternion.real)
    }
}
