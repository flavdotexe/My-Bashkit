## Script de controle e saúde da bateria para Thinkpad T495 com Ryzen 7 3700u

O tlp.conf é específico pra essa máquina e processador, procure outra configuração ideal pra outra máquina específca

## Instalação
```
sudo pacman -S tlp
```
## Serviço
```
sudo systemctl enable tlp.service
sudo systemctl start tlp.service
```
