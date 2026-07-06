extends Node

# Nodo que realizará la petición
@onready var http_request = $HTTPRequest 

func _ready():
	# Conectamos la señal de "petición completada" a nuestra función de manejo
	http_request.request_completed.connect(_on_request_completed)

# Función para enviar la pregunta del usuario
func enviar_pregunta(pregunta_usuario: String):
	var url = "http://localhost:11434/api/generate" # URL por defecto de Ollama
	
	# Preparamos los datos en formato JSON
	var data = {
		"model": "phi3", # O el modelo que descargamos 
		"prompt": pregunta_usuario,
		"stream": false
	}
	
	# Convertimos el diccionario a una cadena JSON
	var json_query = JSON.stringify(data)
	
	# Definimos las cabeceras (headers) obligatorias para POST
	var headers = ["Content-Type: application/json"]
	
	# Realizamos la petición POST
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, json_query)
	
	if error != OK:
		push_error("Error al iniciar la petición HTTP: %d" % error)

# Función que se ejecuta cuando el servidor responde
func _on_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		var respuesta_ia = json["response"]
		print("TecnoBot dice: ", respuesta_ia)
		# Aquí dispararíamos la animación de hablar de Levi [cite: 3805]
	else:
		print("Fallo en el servidor local. Código: ", response_code)
