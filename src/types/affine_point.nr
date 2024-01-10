use dep::aztec::types::type_serialization::TypeSerializationInterface;
use dep::std::ec::tecurve::affine::Point;
use dep::noir_elgamal;

// (x,y)
global AFFINE_POINT_SERIALIZED_LEN = 2;

struct AffinePoint {
    point: Point
}

impl AffinePoint {
    pub fn new(point: Point) -> Self {
        Self {
            point
        }
    }

    fn serialize(self) -> [Field; AFFINE_POINT_SERIALIZED_LEN] {
        [self.point.x, self.point.y]
    }

    pub fn deserialize(serialized: [Field; AFFINE_POINT_SERIALIZED_LEN]) -> Self {
        Self {
            point: Point {
                x: serialized[0],
                y: serialized[1]
            }
        }
    }

    // Add 2 points on BabyJubJub curve
    fn add(self, other: Self) -> Self {
        let bjj_affine = noir_elgamal::get_affine_curve();

        Self {
            point: bjj_affine.add(self.point, other.point)
        }
    }
}

fn deserialize(serialized: [Field; AFFINE_POINT_SERIALIZED_LEN]) -> AffinePoint {
    AffinePoint::deserialize(serialized)
}

fn serialize(value: AffinePoint) -> [Field; AFFINE_POINT_SERIALIZED_LEN] {
    AffinePoint::serialize(value)
}

global AffinePointSerializationMethods = TypeSerializationInterface {
    deserialize,
    serialize
};