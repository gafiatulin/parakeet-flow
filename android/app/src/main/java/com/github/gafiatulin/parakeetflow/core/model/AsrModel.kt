package com.github.gafiatulin.parakeetflow.core.model

enum class AsrModel(
    val displayName: String,
    val description: String,
    val dirName: String,
    val baseUrl: String,
    val files: List<String>,
    val sizeLabel: String,
) {
    PARAKEET_V2(
        displayName = "Parakeet TDT 0.6B v2",
        description = "English only, fastest",
        dirName = "parakeet-tdt-v2",
        baseUrl = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/main",
        files = listOf("encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"),
        sizeLabel = "~660 MB",
    ),
    PARAKEET_V3(
        displayName = "Parakeet TDT 0.6B v3",
        description = "Multilingual (en/de/es/fr)",
        dirName = "parakeet-tdt-v3",
        baseUrl = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main",
        files = listOf("encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"),
        sizeLabel = "~640 MB",
    );
}
