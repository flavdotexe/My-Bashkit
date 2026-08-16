# arch-guardian

Agente interativo de segurança e atualização de pacotes para Arch Linux.

Este projeto substitui o antigo `security-update-arch`. Em vez de um script
que só chama `sudo pacman -Syyu`, o **arch-guardian** oferece um menu
interativo com controle fino sobre o que é atualizado, e gera um relatório
comparando o estado do sistema **antes e depois** de cada atualização.

> O [snapper](https://wiki.archlinux.org/title/Snapper) continua fazendo o
> que sempre fez: o arch-guardian **não gerencia snapshots**, não cria, não
> apaga e não configura o snapper. A única integração é somente leitura
> (`snapper list`) para você ver os snapshots recentes direto do menu.

## Estrutura

```
arch-guardian/
├── guardian.sh              # ponto de entrada, menu interativo
├── modules/
│   ├── packages.sh          # pacman/AUR: updates, tipos de pacotes, kernel
│   ├── services.sh          # systemctl: serviços ativos/afetados/failed
│   ├── network.sh           # ss -tulpn: portas/processos escutando
│   ├── journal.sh           # journalctl: erros correlacionados ao update
│   ├── integrity.sh         # pacman -Qkk, find/stat: .pacnew, configs
│   ├── btrfs.sh              # btrfs + snapper list (somente leitura)
│   └── security.sh          # agrega tudo na tabela de avisos do menu
├── config/
│   └── guardian.conf         # caminhos, pacotes críticos, preferências
├── hooks/
│   └── pacman.hook           # rede de segurança para updates via terminal
└── README.md
```

## Instalação

```bash
git clone https://github.com/flavdotexe/arch-guardian.git
cd arch-guardian
chmod +x guardian.sh
```

Dependências (a maioria já vem em qualquer instalação padrão de Arch):
`pacman`, `iproute2` (ss), `systemd` (systemctl/journalctl), `findutils`
(find), `coreutils` (stat, comm, diff, sort). Opcionalmente `btrfs-progs` e
`snapper` para o módulo BTRFS, e `yay` ou `paru` para atualizações AUR.

Rode diretamente do diretório clonado:

```bash
./guardian.sh
```

Ou instale em `/opt` para rodar de qualquer lugar:

```bash
sudo mkdir -p /opt/arch-guardian
sudo cp -r . /opt/arch-guardian
sudo ln -s /opt/arch-guardian/guardian.sh /usr/local/bin/guardian
```

### Hook do pacman (opcional)

Se você às vezes atualiza pelo terminal direto (`sudo pacman -Syu`) sem
passar pelo menu, instale o hook para deixar um registro no journal:

```bash
sudo cp hooks/pacman.hook /etc/pacman.d/hooks/95-arch-guardian.hook
```

Isso não substitui, não conflita e não interfere nos hooks do snapper
(`snapper-pacman-hooks` ou equivalente) — eles continuam rodando
normalmente e de forma independente.

## Uso

Ao abrir, o `guardian.sh` mostra uma tabela de status logo abaixo do menu:

- Pacotes **críticos** (`linux`, `systemd`, `glibc`, `openssl`, `openssh`,
  `sudo`, `bash`, `pacman`, etc. — lista configurável) com atualização
  pendente
- Total de atualizações pendentes
- Pacotes órfãos
- Serviços systemd **ativos** cujo pacote tem atualização pendente
- Serviços em estado `FAILED`
- Arquivos de configuração modificados localmente em pacotes com
  atualização pendente
- Arquivos `.pacnew` / `.pacsave` existentes em `/etc`
- Espaço livre estimado no BTRFS (se aplicável)
- Saúde da última atualização registrada (OK / FALHOU)

Depois vem o menu:

| Opção | Ação |
|---|---|
| 1 | Atualização completa do sistema (`pacman -Syu`) |
| 2 | Atualizar apenas repositórios oficiais |
| 3 | Atualizar apenas pacotes AUR (via `yay`/`paru`) |
| 4 | Ver pacotes disponíveis para atualização |
| 5 | Tipos de pacotes (explícitos, dependências, órfãos, grupos, estrangeiros) |
| 6 | Informações do kernel (versão em execução vs. instalada, imagens em `/boot`) |
| 7 | Ver log da última atualização |
| 8 | BTRFS / Snapper (somente leitura) |
| 9 | Verificar integridade de pacotes/configs |
| 0 | Sair |

Toda vez que você atualiza pelas opções 1, 2 ou 3, o guardian:

1. Tira uma "foto" do sistema **antes** (rede, serviços, pacotes,
   `.pacnew`, BTRFS)
2. Executa a atualização
3. Tira outra foto **depois**
4. Compara as duas e escreve o relatório em texto

## Log de atualização

O relatório da última atualização é salvo em:

```
/home/fl4v1c0r3/Documents/Logs/update arch/log.txt
```

(caminho configurável em `config/guardian.conf`, variável `LOG_FILE`). Cada
execução **sobrescreve** o log anterior — é sempre o relatório da última
atualização, não um histórico acumulado.

O relatório reúne:

- **Pacotes** — o que foi atualizado, instalado ou removido
- **Serviços** (`systemctl`) — o que parou/começou a rodar, e o que ficou
  `FAILED`
- **Rede** (`ss -tulpn`) — portas/processos que pararam ou começaram a
  escutar
- **Journal** (`journalctl`) — erros registrados durante a janela da
  atualização
- **Integridade** (`find` + `stat`) — novos `.pacnew`/`.pacsave` gerados,
  com dono e data de modificação
- **BTRFS** — uso do sistema de arquivos antes/depois

## Configuração

Tudo fica em `config/guardian.conf`:

```bash
LOG_BASE_DIR="/home/fl4v1c0r3/Documents/Logs/update arch"
STATE_DIR="${HOME}/.local/state/arch-guardian"
CRITICAL_PACKAGES=(linux systemd glibc openssl openssh sudo bash pacman ...)
AUR_HELPER="auto"      # auto | yay | paru | none
COLOR_OUTPUT=true
JOURNAL_ERROR_PRIORITY=3
BTRFS_ENABLED="auto"   # auto | true | false
SNAPPER_CONFIG="root"
```

## Licença

Uso pessoal, sem garantias. Ajuste os caminhos em `guardian.conf` antes de
usar em outra máquina.
