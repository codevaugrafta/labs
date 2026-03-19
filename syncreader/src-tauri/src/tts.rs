use crate::commands::WordTimestamp;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone)]
pub enum TTSProvider {
    ElevenLabs,
    Gemini,
    Inworld,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TTSResult {
    /// Absolute path of the written audio file.
    pub audio_path: String,
    /// Word-level timestamps when the provider returns alignment data.
    /// `None` means forced alignment via the Python sidecar is required.
    pub timestamps: Option<Vec<WordTimestamp>>,
}

pub async fn generate(
    text: &str,
    provider: TTSProvider,
    voice: &str,
    api_key: &str,
    output_dir: &str,
) -> Result<TTSResult, String> {
    // Ensure the output directory exists before any provider tries to write.
    std::fs::create_dir_all(output_dir)
        .map_err(|e| format!("Failed to create output directory '{}': {}", output_dir, e))?;

    match provider {
        TTSProvider::ElevenLabs => generate_elevenlabs(text, voice, api_key, output_dir).await,
        TTSProvider::Gemini => generate_gemini(text, voice, api_key, output_dir).await,
        TTSProvider::Inworld => generate_inworld(text, voice, api_key, output_dir).await,
    }
}

// ---------------------------------------------------------------------------
// ElevenLabs
// ---------------------------------------------------------------------------

async fn generate_elevenlabs(
    text: &str,
    voice_id: &str,
    api_key: &str,
    output_dir: &str,
) -> Result<TTSResult, String> {
    let client = reqwest::Client::new();
    let url = format!(
        "https://api.elevenlabs.io/v1/text-to-speech/{}/with-timestamps",
        voice_id
    );

    #[derive(Serialize)]
    struct ELRequest<'a> {
        text: &'a str,
        model_id: &'static str,
    }

    #[derive(Deserialize)]
    struct ELResponse {
        audio_base64: String,
        alignment: ELAlignment,
    }

    #[derive(Deserialize)]
    struct ELAlignment {
        characters: Vec<String>,
        character_start_times_seconds: Vec<f64>,
        character_end_times_seconds: Vec<f64>,
    }

    let response = client
        .post(&url)
        .header("xi-api-key", api_key)
        .header("Content-Type", "application/json")
        .json(&ELRequest {
            text,
            model_id: "eleven_multilingual_v2",
        })
        .send()
        .await
        .map_err(|e| format!("ElevenLabs request failed: {}", e))?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("ElevenLabs API error {}: {}", status, body));
    }

    let el_response: ELResponse = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse ElevenLabs response: {}", e))?;

    let audio_bytes = base64_decode(&el_response.audio_base64)?;
    let audio_filename = format!("{}.mp3", uuid::Uuid::new_v4());
    let audio_path = Path::new(output_dir).join(&audio_filename);
    std::fs::write(&audio_path, &audio_bytes)
        .map_err(|e| format!("Failed to save ElevenLabs audio: {}", e))?;

    let timestamps = chars_to_word_timestamps(
        &el_response.alignment.characters,
        &el_response.alignment.character_start_times_seconds,
        &el_response.alignment.character_end_times_seconds,
    );

    Ok(TTSResult {
        audio_path: audio_path.to_string_lossy().to_string(),
        timestamps: Some(timestamps),
    })
}

// ---------------------------------------------------------------------------
// Gemini
// ---------------------------------------------------------------------------

async fn generate_gemini(
    text: &str,
    voice: &str,
    api_key: &str,
    output_dir: &str,
) -> Result<TTSResult, String> {
    let client = reqwest::Client::new();
    let url = format!(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key={}",
        api_key
    );

    // Build the request body using serde_json::json! to avoid a large struct tree.
    let request_body = serde_json::json!({
        "contents": [{ "parts": [{ "text": text }] }],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {
                "voiceConfig": {
                    "prebuiltVoiceConfig": {
                        "voiceName": if voice.is_empty() { "Kore" } else { voice }
                    }
                }
            }
        }
    });

    let response = client
        .post(&url)
        .json(&request_body)
        .send()
        .await
        .map_err(|e| format!("Gemini request failed: {}", e))?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("Gemini API error {}: {}", status, body));
    }

    let body: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse Gemini response: {}", e))?;

    let audio_b64 = body["candidates"][0]["content"]["parts"][0]["inlineData"]["data"]
        .as_str()
        .ok_or_else(|| {
            format!(
                "No audio data in Gemini response. Full response: {}",
                body
            )
        })?;

    let audio_bytes = base64_decode(audio_b64)?;
    // Gemini returns linear PCM wrapped in a WAV container.
    let audio_filename = format!("{}.wav", uuid::Uuid::new_v4());
    let audio_path = Path::new(output_dir).join(&audio_filename);
    std::fs::write(&audio_path, &audio_bytes)
        .map_err(|e| format!("Failed to save Gemini audio: {}", e))?;

    // Gemini TTS does not return alignment data — caller must run forced alignment.
    Ok(TTSResult {
        audio_path: audio_path.to_string_lossy().to_string(),
        timestamps: None,
    })
}

// ---------------------------------------------------------------------------
// Inworld
// ---------------------------------------------------------------------------

async fn generate_inworld(
    text: &str,
    voice: &str,
    api_key: &str,
    output_dir: &str,
) -> Result<TTSResult, String> {
    let client = reqwest::Client::new();

    let request_body = serde_json::json!({
        "text": text,
        "voice": if voice.is_empty() { "default" } else { voice }
    });

    let response = client
        .post("https://api.inworld.ai/v1/tts")
        .header("Authorization", format!("Bearer {}", api_key))
        .header("Content-Type", "application/json")
        .json(&request_body)
        .send()
        .await
        .map_err(|e| format!("Inworld request failed: {}", e))?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("Inworld API error {}: {}", status, body));
    }

    let audio_bytes = response
        .bytes()
        .await
        .map_err(|e| format!("Failed to read Inworld response body: {}", e))?;

    let audio_filename = format!("{}.mp3", uuid::Uuid::new_v4());
    let audio_path = Path::new(output_dir).join(&audio_filename);
    std::fs::write(&audio_path, &audio_bytes)
        .map_err(|e| format!("Failed to save Inworld audio: {}", e))?;

    // Inworld TTS does not return alignment data — caller must run forced alignment.
    Ok(TTSResult {
        audio_path: audio_path.to_string_lossy().to_string(),
        timestamps: None,
    })
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Convert ElevenLabs character-level timestamp arrays into word-level timestamps.
///
/// Characters that are whitespace flush the current word accumulator.
/// Sentence-terminal punctuation (`.`, `!`, `?`) increments `sentence_index`
/// after the word containing that character is pushed.
fn chars_to_word_timestamps(
    characters: &[String],
    starts: &[f64],
    ends: &[f64],
) -> Vec<WordTimestamp> {
    assert_eq!(
        characters.len(),
        starts.len(),
        "characters and start arrays must have equal length"
    );
    assert_eq!(
        characters.len(),
        ends.len(),
        "characters and end arrays must have equal length"
    );

    let mut timestamps: Vec<WordTimestamp> = Vec::new();
    let mut current_word = String::new();
    let mut word_start: Option<f64> = None;
    let mut word_end: f64 = 0.0;
    let mut sentence_index: usize = 0;

    let flush = |word: &mut String,
                 w_start: &mut Option<f64>,
                 w_end: f64,
                 s_idx: usize,
                 out: &mut Vec<WordTimestamp>| {
        if !word.is_empty() {
            out.push(WordTimestamp {
                word: word.clone(),
                start: w_start.unwrap_or(0.0),
                end: w_end,
                sentence_index: s_idx,
            });
            word.clear();
            *w_start = None;
        }
    };

    for (i, ch) in characters.iter().enumerate() {
        let ch_str = ch.as_str();

        // Whitespace: flush the current word (no sentence-index bump).
        if ch_str == " " || ch_str == "\n" || ch_str == "\r" {
            flush(
                &mut current_word,
                &mut word_start,
                word_end,
                sentence_index,
                &mut timestamps,
            );
            continue;
        }

        // Start a new word if needed.
        if word_start.is_none() {
            word_start = Some(starts[i]);
        }
        word_end = ends[i];
        current_word.push_str(ch_str);

        // Sentence-terminal punctuation: flush and bump the sentence counter.
        if ch_str == "." || ch_str == "!" || ch_str == "?" {
            flush(
                &mut current_word,
                &mut word_start,
                word_end,
                sentence_index,
                &mut timestamps,
            );
            sentence_index += 1;
        }
    }

    // Flush any remaining word at the end of the text.
    flush(
        &mut current_word,
        &mut word_start,
        word_end,
        sentence_index,
        &mut timestamps,
    );

    timestamps
}

/// Minimal, dependency-free Base64 decoder.
///
/// Whitespace in the input is silently ignored (common in API responses).
/// Returns `Err` on any invalid character.
fn base64_decode(input: &str) -> Result<Vec<u8>, String> {
    let table: [i8; 128] = {
        let mut t = [-1i8; 128];
        for (i, &c) in b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            .iter()
            .enumerate()
        {
            t[c as usize] = i as i8;
        }
        t['=' as usize] = 0; // padding
        t
    };

    let cleaned: Vec<u8> = input
        .bytes()
        .filter(|b| !b.is_ascii_whitespace())
        .collect();

    let mut result = Vec::with_capacity((cleaned.len() / 4) * 3);

    for chunk in cleaned.chunks(4) {
        if chunk.len() < 4 {
            break; // trailing incomplete chunk — ignore
        }
        let decode_byte = |b: u8| -> Result<u8, String> {
            if b as usize >= 128 || table[b as usize] < 0 {
                Err(format!("Invalid Base64 byte: 0x{:02X}", b))
            } else {
                Ok(table[b as usize] as u8)
            }
        };

        let b0 = decode_byte(chunk[0])?;
        let b1 = decode_byte(chunk[1])?;
        let b2 = decode_byte(chunk[2])?;
        let b3 = decode_byte(chunk[3])?;

        result.push((b0 << 2) | (b1 >> 4));
        if chunk[2] != b'=' {
            result.push((b1 << 4) | (b2 >> 2));
        }
        if chunk[3] != b'=' {
            result.push((b2 << 6) | b3);
        }
    }

    Ok(result)
}
