from flask import Flask, request, jsonify
from faster_whisper import WhisperModel
import os

app = Flask(__name__)

print("--- INICIANDO SISTEMA AUDITIVO DE SOFTO ---")
print("Cargando modelo de IA (Tiny) en CPU... Por favor espera.")

# CONFIGURACIÓN CRÍTICA PARA TU HARDWARE:
# device="cpu": Protege tus 496MB de VRAM.
# compute_type="int8": Usa menos RAM y acelera el Ryzen 7.
modelo = WhisperModel("tiny", device="cpu", compute_type="int8")

print("¡Modelo cargado con éxito! Las orejas de Softo están activas en el puerto 5000.")

@app.route('/transcribir', methods=['POST'])
def transcribir_audio():
    # Verificamos que Godot nos haya enviado un archivo
    if 'audio' not in request.files:
        return jsonify({"error": "No se recibió ningún archivo de audio."}), 400
        
    archivo_audio = request.files['audio']
    ruta_temporal = "temp_audio.wav"
    
    # Guardamos temporalmente el audio que manda Godot
    archivo_audio.save(ruta_temporal)
    
    try:
        print("Traduciendo voz a texto...")
        # Forzamos el idioma español ("es") para mayor velocidad y precisión
        segmentos, _ = modelo.transcribe(ruta_temporal, language="es", vad_filter=True, vad_parameters=dict(min_silence_duration_ms=500))
        texto_completo = "".join([segmento.text for segmento in segmentos])
        print(f"DEBUG - Texto transcrito crudo: '{texto_completo}'")
        # Borramos el audio temporal para no llenar tu disco duro
        os.remove(ruta_temporal)
        
        texto_final = texto_completo.strip()
        print(f">>> Usuario dijo: {texto_final}")
        
        # Le devolvemos el texto a Godot
        return jsonify({"texto": texto_final})
        
    except Exception as e:
        print(f"Error en la transcripción: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    # Encendemos el servidor local en el puerto 5000
    app.run(host='127.0.0.1', port=5000)