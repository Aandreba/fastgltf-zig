#include <fastgltf/core.hpp>
#include <fastgltf/types.hpp>

bool load(std::filesystem::path path) {
  // Creates a Parser instance. Optimally, you should reuse this across loads,
  // but don't use it across threads. To enable extensions, you have to pass
  // them into the parser's constructor.
  fastgltf::Parser parser;

  // The GltfDataBuffer class contains static factories which create a buffer
  // for holding the glTF data. These return Expected<GltfDataBuffer>, which can
  // be checked if an error occurs. The parser accepts any subtype of
  // GltfDataGetter, which defines an interface for reading chunks of the glTF
  // file for the Parser to handle. fastgltf provides a few predefined classes
  // which inherit from GltfDataGetter, so choose whichever fits your usecase
  // the best.
  auto data = fastgltf::GltfDataBuffer::FromPath(path);
  if (data.error() != fastgltf::Error::None) {
    // The file couldn't be loaded, or the buffer could not be allocated.
    return false;
  }

  // This loads the glTF file into the gltf object and parses the JSON.
  // It automatically detects whether this is a JSON-based or binary glTF.
  // If you know the type, you can also use loadGltfJson or loadGltfBinary.
  auto asset =
      parser.loadGltf(data.get(), path.parent_path(), fastgltf::Options::None);
  if (auto error = asset.error(); error != fastgltf::Error::None) {
    // Some error occurred while reading the buffer, parsing the JSON, or
    // validating the data.
    return false;
  }

  // The glTF 2.0 asset is now ready to be used. Simply call asset.get(),
  // asset.get_if() or asset-> to get a direct reference to the Asset class. You
  // can then access the glTF data structures, like, for example, with buffers:
  for (auto &buffer : asset->buffers) {
    // Process the buffers.
  }

  // Optionally, you can now also call the fastgltf::validate method. This will
  // more strictly enforce the glTF spec and is not needed most of the time,
  // though I would certainly recommend it in a development environment or when
  // debugging to avoid mishaps.

  // fastgltf::validate(asset.get());

  return true;
}

int main() { return 0; }
