"""
Gera os ícones do app Android a partir do ícone do DECI (tools/deci-icone-original.webp).

- Corta os cantos (a imagem original vem com cantos pretos) -> tools/deci-icone.png
- Ícones clássicos: res/mipmap-*/ic_launcher.png (48..192 px)
- Ícones adaptativos (Android 8+): fundo creme + frente com o blob dentro da "zona segura",
  para a máscara redonda/arredondada do celular não cortar o personagem.

Uso (dentro de mobile/): python tools/gerar_icones_android.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

RAIZ = Path(__file__).resolve().parent.parent
ORIGINAL = RAIZ / 'tools' / 'deci-icone-original.webp'
RES = RAIZ / 'android' / 'app' / 'src' / 'main' / 'res'
CREME = '#FEF1EC'
RAIO = 0.19  # raio dos cantos do ícone original, em fração do lado (medido: ~239 px de 1254)
LARGURA_BLOB = 0.777  # largura do blob em fração da imagem (medida no original)
DENSIDADES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def icone_limpo(lado=1024):
    im = Image.open(ORIGINAL).convert('RGBA').resize((lado, lado), Image.LANCZOS)
    mascara = Image.new('L', (lado * 4, lado * 4), 0)
    ImageDraw.Draw(mascara).rounded_rectangle([0, 0, lado * 4 - 1, lado * 4 - 1], radius=int(RAIO * lado * 4), fill=255)
    im.putalpha(mascara.resize((lado, lado), Image.LANCZOS))  # supersampling = borda suave
    return im


def main():
    limpo = icone_limpo()
    limpo.save(RAIZ / 'tools' / 'deci-icone.png', optimize=True)

    for nome, d in DENSIDADES.items():
        pasta = RES / f'mipmap-{nome}'
        pasta.mkdir(exist_ok=True)
        lado = round(48 * d)
        limpo.resize((lado, lado), Image.LANCZOS).save(pasta / 'ic_launcher.png', optimize=True)
        # adaptativo: tela de 108 dp; o círculo visível tem ~66 dp -> blob com ~56% da largura
        tela = round(108 * d)
        img = round(tela * 0.56 / LARGURA_BLOB)
        frente = Image.new('RGBA', (tela, tela), (0, 0, 0, 0))
        frente.alpha_composite(limpo.resize((img, img), Image.LANCZOS), ((tela - img) // 2, (tela - img) // 2))
        frente.save(pasta / 'ic_launcher_foreground.png', optimize=True)

    v26 = RES / 'mipmap-anydpi-v26'
    v26.mkdir(exist_ok=True)
    (v26 / 'ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n', encoding='utf-8')
    (RES / 'values' / 'cores_deci.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">{CREME}</color>\n'
        f'    <color name="deci_creme">{CREME}</color>\n</resources>\n', encoding='utf-8')
    print('Ícones gerados em', RES)


if __name__ == '__main__':
    main()
