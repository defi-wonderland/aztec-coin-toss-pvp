use dep::aztec::types::type_serialization::TypeSerializationInterface;
use dep::std::ec::tecurve::affine::Point;
use dep::noir_elgamal;

// (x,y)
global AFFINE_POINT_SERIALIZED_LEN = 2;

/// @notice A struct composing over the Point struct
/// @member point<Point> An element representing a point on the Baby Jubjub curve.
struct AffinePoint {
    point: Point
}

impl AffinePoint {
    /// @notice Creates a new AffinePoint starting from a Point
    /// @param point The point to be wrapped and extended
    pub fn new(point: Point) -> Self {
        Self {
            point
        }
    }

    /// @notice Serializes an AffinePoint into an array of Field elements
    fn serialize(self) -> [Field; AFFINE_POINT_SERIALIZED_LEN] {
        [self.point.x, self.point.y]
    }

    /// @notice Deserializes an array of Field elements into an AffinePoint
    /// @param serialized The array of Field elements to be deserialized
    pub fn deserialize(serialized: [Field; AFFINE_POINT_SERIALIZED_LEN]) -> Self {
        Self {
            point: Point {
                x: serialized[0],
                y: serialized[1]
            }
        }
    }

    /// @notice Adds two AffinePoints together (in the Baby Jubjub curve)
    /// @param other The other AffinePoint to be added
    fn add(self, other: Self) -> Self {
        let bjj_affine = noir_elgamal::get_affine_curve();

        Self {
            point: bjj_affine.add(self.point, other.point)
        }
    }

    /// @notice Checks whether two AffinePoints are equal (in the Baby Jubjub curve)
    /// @param other The other AffinePoint to be compared
    fn eq(self, other: Self) -> bool {
        self.point.eq(other.point)
    }
}

// "traits are experimental and not yet fully implemented"
// impl Eq for AffinePoint {
// }

/// @notice Deserializes an array of Field elements into an AffinePoint
/// @param serialized The array of Field elements to be deserialized
fn deserialize(serialized: [Field; AFFINE_POINT_SERIALIZED_LEN]) -> AffinePoint {
    AffinePoint::deserialize(serialized)
}
/// @notice Serializes an AffinePoint into an array of Field elements
/// @param value The AffinePoint to be serialized
fn serialize(value: AffinePoint) -> [Field; AFFINE_POINT_SERIALIZED_LEN] {
    AffinePoint::serialize(value)
}

global AffinePointSerializationMethods = TypeSerializationInterface {
    deserialize,
    serialize
};