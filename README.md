# WindowMenu

Barra de tareas estilo Windows en la barra de menús de macOS: cada ventana del monitor/Space activo aparece como un botón (icono + título).

- **Ventana con foco:** fondo resaltado, título en negrita y una rayita de color de acento.
- **Clic en una ventana:** la enfoca. Clic en la activa: la minimiza. Clic en una minimizada (atenuada): la restaura.
- **Orden estable:** los botones no cambian de sitio al cambiar el foco.
- **Clic derecho:** mostrar/ocultar títulos, ancho máximo, abrir al iniciar sesión, salir.

## Compilar
```bash
./build.sh
mv WindowMenu.app /Applications/ && open /Applications/WindowMenu.app
```
Requiere macOS 13+ y Xcode o las Command Line Tools (`xcode-select --install`).

## Permisos
- **Accesibilidad** (obligatorio): Ajustes del Sistema → Privacidad y seguridad → Accesibilidad.
- Cada recompilación cambia la firma ad-hoc: si deja de funcionar, quítala de la lista de Accesibilidad y vuelve a añadirla.

## Notas
- **Una barra por monitor**, cada una con las ventanas de ese monitor en su Space actual. Es un panel flotante colocado sobre la barra de menús, entre los menús de la app y los iconos de la derecha (se adapta al notch).
- El icono ▢ de la barra de menús abre los ajustes: títulos, ancho máximo, posición (junto a los iconos o junto a los menús), inicio de sesión y salir. También con clic derecho sobre la barra.
- No aparece sobre apps a pantalla completa ni cuando la barra de menús está oculta automáticamente.
