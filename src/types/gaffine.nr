use dep::aztec::types::type_serialization::TypeSerializationInterface;
use dep::std::ec::tecurve::affine::Point as Gaffine;

global GAFFINE_SERIALIZED_LEN = 2;

global GaffineSerializationMethods = TypeSerializationInterface {
    deserialize: | serialized: [Field; GAFFINE_SERIALIZED_LEN] | Gaffine{x: serialized[0], y: serialized[1]},
    serialize: | value: Gaffine | [value.x, value.y]
};