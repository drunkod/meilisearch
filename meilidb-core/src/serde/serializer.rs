use meilidb_schema::{Schema, SchemaAttr};
use serde::ser;
use std::collections::HashMap;

use crate::raw_indexer::RawIndexer;
use crate::serde::RamDocumentStore;
use crate::{DocumentId, RankedMap};

use super::{ConvertToNumber, ConvertToString, Indexer, SerializerError};

pub struct Serializer<'a> {
    pub schema: &'a Schema,
    pub document_store: &'a mut RamDocumentStore,
    pub document_fields_counts: &'a mut HashMap<(DocumentId, SchemaAttr), u64>,
    pub indexer: &'a mut RawIndexer,
    pub ranked_map: &'a mut RankedMap,
    pub document_id: DocumentId,
}

impl<'a> ser::Serializer for Serializer<'a> {
    type Ok = ();
    type Error = SerializerError;
    type SerializeSeq = ser::Impossible<Self::Ok, Self::Error>;
    type SerializeTuple = ser::Impossible<Self::Ok, Self::Error>;
    type SerializeTupleStruct = ser::Impossible<Self::Ok, Self::Error>;
    type SerializeTupleVariant = ser::Impossible<Self::Ok, Self::Error>;
    type SerializeMap = MapSerializer<'a>;
    type SerializeStruct = StructSerializer<'a>;
    type SerializeStructVariant = ser::Impossible<Self::Ok, Self::Error>;

    forward_to_unserializable_type! {
        bool => serialize_bool,
        char => serialize_char,

        i8  => serialize_i8,
        i16 => serialize_i16,
        i32 => serialize_i32,
        i64 => serialize_i64,

        u8  => serialize_u8,
        u16 => serialize_u16,
        u32 => serialize_u32,
        u64 => serialize_u64,

        f32 => serialize_f32,
        f64 => serialize_f64,
    }

    fn serialize_str(self, _v: &str) -> Result<Self::Ok, Self::Error> {
        Err(SerializerError::UnserializableType { type_name: "str" })
    }

    fn serialize_bytes(self, _v: &[u8]) -> Result<Self::Ok, Self::Error> {
        Err(SerializerError::UnserializableType { type_name: "&[u8]" })
    }

    fn serialize_none(self) -> Result<Self::Ok, Self::Error> {
        Err(SerializerError::UnserializableType {
            type_name: "Option",
        })
    }

    fn serialize_some<T: ?Sized>(self, _value: &T) -> Result<Self::Ok, Self::Error>
    where
        T: ser::Serialize,
    {
        Err(SerializerError::UnserializableType {
            type_name: "Option",
        })
    }

    fn serialize_unit(self) -> Result<Self::Ok, Self::Error> {
        Err(SerializerError::UnserializableType { type_name: "()" })
    }

    fn serialize_unit_struct(self, _name: &'static str) -> Result<Self::Ok, Self::Error> {
        Err(SerializerError::UnserializableType {
            type_name: "unit struct",
        })
    }

    fn serialize_unit_variant(
        self,
        _name: &'static str,
        _variant_index: u32,
        _variant: &'static str,
    ) -> Result<Self::Ok, Self::Error> {
        Err(SerializerError::UnserializableType {
            type_name: "unit variant",
        })
    }

    fn serialize_newtype_struct<T: ?Sized>(
        self,
        _name: &'static str,
        value: &T,
    ) -> Result<Self::Ok, Self::Error>
    where
        T: ser::Serialize,
    {
        value.serialize(self)
    }

    fn serialize_newtype_variant<T: ?Sized>(
        self,
        _name: &'static str,
        _variant_index: u32,
        _variant: &'static str,
        _value: &T,
    ) -> Result<Self::Ok, Self::Error>
    where
        T: ser::Serialize,
    {
        Err(SerializerError::UnserializableType {
            type_name: "newtype variant",
        })
    }

    fn serialize_seq(self, _len: Option<usize>) -> Result<Self::SerializeSeq, Self::Error> {
        Err(SerializerError::UnserializableType {
            type_name: "sequence",
        })
    }

    fn serialize_tuple(self, _len: usize) -> Result<Self::SerializeTuple, Self::Error> {
        Err(SerializerError::UnserializableType { type_name: "tuple" })
    }

    fn serialize_tuple_struct(
        self,
        _name: &'static str,
        _len: usize,
    ) -> Result<Self::SerializeTupleStruct, Self::Error> {
        Err(SerializerError::UnserializableType {
            type_name: "tuple struct",
        })
    }

    fn serialize_tuple_variant(
        self,
        _name: &'static str,
        _variant_index: u32,
        _variant: &'static str,
        _len: usize,
    ) -> Result<Self::SerializeTupleVariant, Self::Error> {
        Err(SerializerError::UnserializableType {
            type_name: "tuple variant",
        })
    }

    fn serialize_map(self, _len: Option<usize>) -> Result<Self::SerializeMap, Self::Error> {
        Ok(MapSerializer {
            schema: self.schema,
            document_id: self.document_id,
            document_store: self.document_store,
            document_fields_counts: self.document_fields_counts,
            indexer: self.indexer,
            ranked_map: self.ranked_map,
            current_key_name: None,
        })
    }

    fn serialize_struct(
        self,
        _name: &'static str,
        _len: usize,
    ) -> Result<Self::SerializeStruct, Self::Error> {
        Ok(StructSerializer {
            schema: self.schema,
            document_id: self.document_id,
            document_store: self.document_store,
            document_fields_counts: self.document_fields_counts,
            indexer: self.indexer,
            ranked_map: self.ranked_map,
        })
    }

    fn serialize_struct_variant(
        self,
        _name: &'static str,
        _variant_index: u32,
        _variant: &'static str,
        _len: usize,
    ) -> Result<Self::SerializeStructVariant, Self::Error> {
        Err(SerializerError::UnserializableType {
            type_name: "struct variant",
        })
    }
}

pub struct MapSerializer<'a> {
    schema: &'a Schema,
    document_id: DocumentId,
    document_store: &'a mut RamDocumentStore,
    document_fields_counts: &'a mut HashMap<(DocumentId, SchemaAttr), u64>,
    indexer: &'a mut RawIndexer,
    ranked_map: &'a mut RankedMap,
    current_key_name: Option<String>,
}

impl<'a> ser::SerializeMap for MapSerializer<'a> {
    type Ok = ();
    type Error = SerializerError;

    fn serialize_key<T: ?Sized>(&mut self, key: &T) -> Result<(), Self::Error>
    where
        T: ser::Serialize,
    {
        let key = key.serialize(ConvertToString)?;
        self.current_key_name = Some(key);
        Ok(())
    }

    fn serialize_value<T: ?Sized>(&mut self, value: &T) -> Result<(), Self::Error>
    where
        T: ser::Serialize,
    {
        let key = self.current_key_name.take().unwrap();
        self.serialize_entry(&key, value)
    }

    fn serialize_entry<K: ?Sized, V: ?Sized>(
        &mut self,
        key: &K,
        value: &V,
    ) -> Result<(), Self::Error>
    where
        K: ser::Serialize,
        V: ser::Serialize,
    {
        let key = key.serialize(ConvertToString)?;

        serialize_value(
            self.schema,
            self.document_id,
            self.document_store,
            self.document_fields_counts,
            self.indexer,
            self.ranked_map,
            &key,
            value,
        )
    }

    fn end(self) -> Result<Self::Ok, Self::Error> {
        Ok(())
    }
}

pub struct StructSerializer<'a> {
    schema: &'a Schema,
    document_id: DocumentId,
    document_store: &'a mut RamDocumentStore,
    document_fields_counts: &'a mut HashMap<(DocumentId, SchemaAttr), u64>,
    indexer: &'a mut RawIndexer,
    ranked_map: &'a mut RankedMap,
}

impl<'a> ser::SerializeStruct for StructSerializer<'a> {
    type Ok = ();
    type Error = SerializerError;

    fn serialize_field<T: ?Sized>(
        &mut self,
        key: &'static str,
        value: &T,
    ) -> Result<(), Self::Error>
    where
        T: ser::Serialize,
    {
        serialize_value(
            self.schema,
            self.document_id,
            self.document_store,
            self.document_fields_counts,
            self.indexer,
            self.ranked_map,
            key,
            value,
        )
    }

    fn end(self) -> Result<Self::Ok, Self::Error> {
        Ok(())
    }
}

fn serialize_value<T: ?Sized>(
    schema: &Schema,
    document_id: DocumentId,
    document_store: &mut RamDocumentStore,
    documents_fields_counts: &mut HashMap<(DocumentId, SchemaAttr), u64>,
    indexer: &mut RawIndexer,
    ranked_map: &mut RankedMap,
    key: &str,
    value: &T,
) -> Result<(), SerializerError>
where
    T: ser::Serialize,
{
    if let Some(attribute) = schema.attribute(key) {
        let props = schema.props(attribute);

        let serialized = serde_json::to_vec(value)?;
        document_store.set_document_field(document_id, attribute, serialized);

        if props.is_indexed() {
            let indexer = Indexer {
                attribute,
                indexer,
                document_id,
            };
            if let Some(number_of_words) = value.serialize(indexer)? {
                documents_fields_counts.insert((document_id, attribute), number_of_words as u64);
            }
        }

        if props.is_ranked() {
            let number = value.serialize(ConvertToNumber)?;
            ranked_map.insert(document_id, attribute, number);
        }
    }

    Ok(())
}
