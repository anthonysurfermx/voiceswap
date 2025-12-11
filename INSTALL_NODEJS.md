# Instalar Node.js en macOS

## Opción 1: Descarga Directa (Más Fácil)

1. **Descarga el instalador:**
   - Ve a: https://nodejs.org/
   - Click en el botón verde "Download Node.js (LTS)"
   - Descarga la versión LTS para macOS

2. **Ejecuta el instalador:**
   - Abre el archivo `.pkg` descargado
   - Sigue el asistente de instalación
   - Acepta los términos y condiciones
   - Click "Install"

3. **Reinicia tu terminal:**
   ```bash
   # Cierra y abre nuevamente tu terminal
   ```

4. **Verifica la instalación:**
   ```bash
   node --version  # Debería mostrar v20.x.x o similar
   npm --version   # Debería mostrar 10.x.x o similar
   ```

---

## Opción 2: Homebrew (Recomendado para Desarrolladores)

### Paso 1: Instalar Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Importante:** Después de instalar, sigue las instrucciones que aparecen en pantalla para añadir Homebrew a tu PATH. Normalmente son estos comandos:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### Paso 2: Instalar Node.js

```bash
brew install node
```

### Paso 3: Verificar

```bash
node --version
npm --version
```

---

## Opción 3: nvm (Para Gestionar Múltiples Versiones)

### Paso 1: Instalar nvm

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
```

### Paso 2: Recargar tu shell

```bash
source ~/.zshrc
```

Si no funciona, añade manualmente a `~/.zshrc`:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
```

### Paso 3: Instalar Node.js

```bash
nvm install --lts
nvm use --lts
```

### Paso 4: Verificar

```bash
node --version
npm --version
```

---

## Después de Instalar Node.js

Una vez instalado, continúa con:

```bash
# 1. Ir al proyecto
cd /Users/mrrobot/Documents/GitHub/voiceswap

# 2. Instalar dependencias
npm install

# 3. Verificar instalación de thirdweb
npm list thirdweb

# 4. Arrancar servidor
npm run dev
```

---

## Troubleshooting

### "command not found: node" después de instalar

**Solución 1:** Reinicia tu terminal completamente (cierra y abre nueva ventana).

**Solución 2:** Verifica que Node.js esté en tu PATH:
```bash
echo $PATH
```

Debería incluir algo como `/usr/local/bin` o `/opt/homebrew/bin`.

**Solución 3:** Añade manualmente a tu PATH en `~/.zshrc`:
```bash
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Error de permisos al instalar Homebrew

Homebrew puede requerir permisos de administrador. Ejecuta:
```bash
sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Error "xcrun: error: invalid active developer path"

Necesitas instalar las Xcode Command Line Tools:
```bash
xcode-select --install
```

---

## Recomendación

Para la **instalación más rápida**:
1. Ve a https://nodejs.org/
2. Descarga el instalador LTS
3. Ejecuta el `.pkg`
4. Reinicia terminal
5. Verifica con `node --version`

¡Listo en 5 minutos!

---

## Después de Instalar

Continúa con [START_HERE.md](START_HERE.md) para probar el backend.
