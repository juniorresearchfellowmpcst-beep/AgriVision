/// Abstract class defining the interface for storage operations.
/// Implementations should provide persistent storage capabilities for key-value pairs.
abstract class Storage {
  /// Reads a string value from storage for the given [key].
  /// Returns null if the key doesn't exist or an error occurs.
  Future<String?> read({required String key});

  /// Reads a boolean value from storage for the given [key].
  /// Returns null if the key doesn't exist or an error occurs.
  Future<bool?> readBool({required String key});

  /// Writes a string [value] to storage with the given [key].
  /// Throws an exception if the write operation fails.
  Future<void> write({required String key, required String value});

  /// Writes a boolean [value] to storage with the given [key].
  /// Throws an exception if the write operation fails.
  Future<void> writeBool({required String key, required bool value});

  /// Deletes the value associated with the given [key] from storage.
  /// Throws an exception if the delete operation fails.
  Future<void> delete({required String key});

  /// Clears all data from storage.
  /// Throws an exception if the clear operation fails.
  Future<void> clear();
}
