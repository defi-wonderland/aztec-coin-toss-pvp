use dep::aztec::types::type_serialization::TypeSerializationInterface;
use dep::std::ec::tecurve::affine::Point;

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