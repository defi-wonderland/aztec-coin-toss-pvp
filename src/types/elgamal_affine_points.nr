use dep::aztec::types::type_serialization::TypeSerializationInterface;
use dep::std::ec::tecurve::affine::Point;
use crate::types::affine_point::AffinePoint;

// ( (x,y), (x,y) )
global ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN = 4;

struct ElgamalAffinePoints {
    C1: AffinePoint,
    C2: AffinePoint
}

impl ElgamalAffinePoints {
    pub fn new(point_C1: AffinePoint, point_C2: AffinePoint) -> Self {
        Self {
            C1: point_C1,
            C2: point_C2
        }
    }

    fn serialize(self) -> [Field; ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN] {
        [self.C1.point.x, self.C1.point.y, self.C2.point.x, self.C2.point.y]
    }
  
    pub fn deserialize(serialized: [Field; ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN]) -> Self {
        Self {
            C1: AffinePoint::new(Point{
                x: serialized[0],
                y: serialized[1]
            }),
            C2: AffinePoint::new(Point{
                x: serialized[2],
                y: serialized[3]
            })
        }
    }

    // Add 2 encrypted messages
    fn add(self, second: ElgamalAffinePoints) -> Self {
        Self {
            C1: self.C1.add(second.C1),
            C2: self.C2.add(second.C2)
        }
    }
}

fn deserialize(serialized: [Field; ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN]) -> ElgamalAffinePoints {
    ElgamalAffinePoints::deserialize(serialized)
}

fn serialize(value: ElgamalAffinePoints) -> [Field; ELGAMAL_AFFINE_POINTS_SERIALIZED_LEN] {
    ElgamalAffinePoints::serialize(value)
}

global ElgamalAffinePointsSerializationMethods = TypeSerializationInterface {
    deserialize,
    serialize
};