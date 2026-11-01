# Ambiente isolado do REA

Este diretório contém um ambiente reproduzível para desenvolver, testar e
experimentar o REA sem instalar nada globalmente na máquina.

O repositório é um fork de `morluto/rea`:

| Remote     | URL                                          |
| ---------- | -------------------------------------------- |
| `origin`   | `https://github.com/digojulioctba2024/rea`   |
| `upstream` | `https://github.com/morluto/rea`             |

## Duas pistas

| Pista            | Onde roda        | Para quê                                                                 | É fronteira de segurança? |
| ---------------- | ---------------- | ------------------------------------------------------------------------ | ------------------------- |
| **Host Windows** | Windows          | CLI nativa, recursos de PE/Windows, iteração rápida                      | Não                       |
| **Docker `dev`** | Linux (container)| Build, typecheck, testes, desenvolvimento com o código montado ao vivo   | Parcial                   |
| **Docker `lab`** | Linux (container)| Analisar arquivos não confiáveis: sem rede, root FS somente leitura      | Sim, com ressalvas         |
| **Docker `web`** | Linux (container)| Análise de sites/runtimes que precisam de rede                           | Parcial                   |

O `lab` é a pista recomendada para qualquer binário, APK, ASAR, firmware ou
amostra que você não escreveu. Ele não tem rede, roda como UID 1000, com
`cap_drop: ALL`, `no-new-privileges`, limite de memória/CPU/PIDs e somente
`workspace/samples` (leitura) e `workspace/out` (escrita) montados.

> Importante: um container reduz o raio de impacto, mas não é uma garantia
> absoluta contra falhas do kernel, do runtime ou do Docker Desktop. Para
> amostras realmente hostis, use uma VM descartável e sem credenciais.

## Estrutura

```
rea/
├─ .tools/                       Node 24.22.1 portátil + cache npm (ignorado)
├─ node_modules/                 dependências do host (ignorado)
├─ dist/                         build do host (ignorado)
├─ sandbox/
│  ├─ Dockerfile                 imagem Linux com Node, Python, Java e utilitários
│  ├─ compose.yaml               serviços dev, lab e web
│  ├─ scripts/
│  │  ├─ setup.ps1               instala o toolchain local e compila
│  │  ├─ env.ps1                 ativa o Node local no PowerShell
│  │  ├─ sandbox.ps1             atalho para todas as operações
│  │  └─ entrypoint.sh           prepara o volume e reduz privilégios
│  └─ workspace/
│     ├─ samples/                entradas não confiáveis (somente leitura no lab)
│     └─ out/                    resultados (gravável)
└─ .dockerignore
```

## Pré-requisitos

- Windows 10/11 com PowerShell 5.1+
- Docker Desktop com WSL2 (o `lab` usa Linux containers)
- ~6 GB livres em disco para a imagem + volume de `node_modules`
- 8 GB de RAM disponíveis para o Docker Desktop

O Node **não** precisa estar instalado globalmente: o `setup.ps1` baixa a versão
exata do `.nvmrc` (24.22.1) para `.tools/`.

## Início rápido

```powershell
cd C:\Users\Rodrigo\Documents\OpenCode\rea

# 1) Toolchain do host + build + imagem Docker
.\sandbox\scripts\sandbox.ps1 setup

# 2) Shell Linux com o código montado ao vivo
.\sandbox\scripts\sandbox.ps1 shell

# 3) Testes (dentro ou fora do shell)
.\sandbox\scripts\sandbox.ps1 exec npm run test:local -- tests/domain

# 4) CLI nativa do Windows
.\sandbox\scripts\sandbox.ps1 host --help
```

Na primeira vez que o `dev` sobe, ele copia `node_modules` da imagem para um
volume nomeado. Isso leva alguns segundos e só acontece uma vez (ou quando o
`package-lock.json` muda).

## Comandos

```powershell
.\sandbox\scripts\sandbox.ps1 help

setup      Toolchain do host + imagem Docker
build      Reconstrói a imagem
shell      bash interativo no container dev
exec CMD   Executa um comando no container dev
lab CMD    REA offline contra /samples, gravando em /out
web CMD    REA com rede (sites, runtime)
host CMD   CLI REA compilada no host
host-npm   npm/npx no host com o Node local
status     Containers, imagem e uso de disco
down       Remove os containers
reset      Remove containers e volumes (pede confirmação)
```

### Exemplos de análise

Coloque a amostra em `sandbox/workspace/samples/` e rode:

```powershell
# Aplicação JavaScript/Electron (não precisa de rede)
.\sandbox\scripts\sandbox.ps1 lab analyze-javascript-application /samples/app --json

# Binário nativo (precisa de um provider: Ghidra, IDA, Hopper ou Kuna)
.\sandbox\scripts\sandbox.ps1 lab analyze-binary /samples/app.exe --json

# Site (precisa de rede)
.\sandbox\scripts\sandbox.ps1 web analyze-website https://example.com --json
```

Os resultados aparecem em `sandbox/workspace/out/`.

Consulte `sandbox/workspace/README.md` para as regras de montagem.

### Build e testes no container

```powershell
.\sandbox\scripts\sandbox.ps1 exec npm run build:cached
.\sandbox\scripts\sandbox.ps1 exec npm run check:fast
.\sandbox\scripts\sandbox.ps1 exec npm run test:local -- tests/domain
.\sandbox\scripts\sandbox.ps1 exec npm run test:python
```

O código em `C:\Users\Rodrigo\Documents\OpenCode\rea` é montado em `/workspace`,
então edições no Windows aparecem imediatamente no container. O `node_modules`
do container fica em um volume Linux separado e não colide com o do host.

## MCP (opcional)

Para usar o REA como servidor MCP no OpenCode **deste projeto**, crie
`opencode.json` na raiz do repositório:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "rea": {
      "type": "local",
      "command": ["node", "scripts/rea.mjs", "mcp"],
      "enabled": true
    }
  }
}
```

Ou, para manter a análise dentro do container isolado:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "rea-lab": {
      "type": "local",
      "command": [
        "docker", "compose", "-f", "sandbox/compose.yaml",
        "run", "--rm", "-T", "lab", "rea", "mcp"
      ],
      "enabled": true
    }
  }
}
```

Reinicie o OpenCode depois de criar o arquivo. O segundo formato mantém o
processo de análise sem rede e com o sistema de arquivos somente leitura.

## Git: fork e upstream

```powershell
# Atualizar com o projeto original
git fetch upstream
git merge upstream/main

# Publicar suas mudanças no seu fork
git push origin main
```

O fork já existe em `https://github.com/digojulioctba2024/rea`.

## Solução de problemas

**A imagem falha por falta de espaço**

```powershell
docker system df
docker builder prune -f
docker image prune -f
```

O `reset` remove o volume de `node_modules`; o próximo `setup`/`shell` o recria.
Não rode `docker system prune -a` sem revisar: ele remove imagens de outros
projetos.

Esta máquina terminou o setup com ~2,9 GB livres. O Docker Desktop mantém os
dados em um VHDX do WSL2 e nem sempre devolve ao Windows o espaço liberado
dentro do Docker. Se precisar de mais espaço, remova imagens não usadas pelo
painel do Docker Desktop ou compacte o VHDX com o Docker parado.

**`REA Windows native controls are unavailable`**

O artefato nativo do Windows não está no Git, apenas no tarball do npm. O
`sandbox/scripts/setup.ps1` restaura automaticamente a versão que coincide com
`package.json`. Rode o setup novamente.

**Docker não sobe / sem memória**

Ajuste em Docker Desktop → Settings → Resources. O compose limita `dev` a 6 GB,
`lab`/`web` a 3 GB. Com 16 GB de RAM, deixe o Docker com 6–8 GB.

**Primeiro `shell` demora**

É a cópia de `node_modules` da imagem para o volume. As próximas execuções são
imediatas.

**Análise nativa não funciona**

O container não inclui Ghidra/IDA/Hopper. Para análise nativa:
- use a pista do host com um provider instalado; ou
- monte um Ghidra existente no container e configure `JAVA_HOME`/provider.

O REA é "bring-your-own" para esses motores. Análise estática de
JavaScript/Electron, Go, Rust, IL2CPP, Godot, firmware e formatos de modelo
funciona sem provider externo.

## Estado da verificação

Marque apenas o que foi realmente executado nesta máquina:

- [x] `npm ci` no host Windows com Node 24.22.1
- [x] `npm run build:cached` no host
- [x] CLI compilada: `node scripts/rea.mjs --version` → `6.8.0`
- [x] `npm run test:local -- src/config.test.ts` → 84 testes passando (host e container)
- [x] Imagem Docker `rea-sandbox:local` (2,78 GB)
- [x] `lab` offline: `rea --version` → `6.8.0`, DNS indisponível, root FS somente leitura, `/out` gravável
- [x] `dev` com o código montado e `node_modules` em volume
- [x] `lab`: `analyze-javascript-application /samples/demo-app` → 4 arquivos JS, 30 nós, 40 arestas, IPC/preload/contextBridge detectados
- [x] `npm run test:python` no container → 93 testes OK
- [x] `npm run check:fast` no container → typecheck + lint OK
- [x] `sandbox/scripts/verify.ps1` → todos os smoke tests passaram

Rode `sandbox/scripts/verify.ps1` para repetir os smoke tests e
`verify.ps1 -Full` para os checks rápidos + testes Python. Não presuma que uma
pista está verde sem executar o comando.
