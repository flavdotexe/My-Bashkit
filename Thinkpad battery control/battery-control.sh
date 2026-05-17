#!/bin/bash

clear
echo "==============================="
echo "   ThinkPad Battery Control"
echo "==============================="
echo
echo "1) Ativar proteção (75% → 80%)"
echo "2) Liberar carga total (0% → 100%)"
echo "3) Mostrar status da bateria"
echo "4) Descarregar bateria (100% → 80%)"
echo "5) Recalibrar bateria"
echo "6) Sair"
echo
read -rp "Escolha uma opção [1-6]: " choice

case "$choice" in
  1)
    sudo tlp setcharge 75 80 BAT0
    echo
    echo "Proteção ativada! (75–80%)"
    ;;
  2)
    sudo tlp setcharge 0 100 BAT0
    echo
    echo "Carga total liberada! (0–100%)"
    ;;
  3)
    echo
    sudo tlp-stat -b
    ;;
  4) 
    echo
    sudo tlp discharge BAT0
    ;;
  5)
    echo
    echo "ATENÇÃO!!! Calibração da bateria"
    echo
    read -rp "Deseja continuar? (S/n): " confirm

    if [[ "$confirm" =~ ^([sS]|[sS][iI][mM])$ || -z "$confirm" ]]; then
        echo
        echo "Iniciando recalibração da bateria..."
        sudo tlp recalibrate BAT0
    else
        echo
        echo "Operação cancelada."
    fi
    ;;
  6)
    echo "Saindo..."
    exit 0
    ;;
  *)
    echo "❌ Opção inválida"
    ;;
esac

