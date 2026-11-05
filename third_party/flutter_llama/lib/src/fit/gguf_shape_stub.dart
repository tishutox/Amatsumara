/// Web: no files to read.
library;

class GgufShape {
  const GgufShape({required this.architecture, required this.layers, required this.embedding, required this.heads, required this.headsKv, this.keyLength, this.trainedContext, this.name, this.license});
  final String architecture;
  final int layers;
  final int embedding;
  final int heads;
  final int headsKv;
  final int? keyLength;
  final int? trainedContext;
  final String? name;
  final String? license;
  int kvBytes(int context) => 2 * layers * context * (keyLength ?? (heads == 0 ? 0 : embedding ~/ heads)) * headsKv * 2;
}

GgufShape readGgufShape(String path) => throw UnsupportedError('no files on the web');
