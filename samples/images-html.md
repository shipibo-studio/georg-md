# Imágenes y HTML

Local relativa:

![Café local](img/cafe.png)

Web (https):

![Demo PNG](https://upload.wikimedia.org/wikipedia/commons/4/47/PNG_transparency_demonstration_1.png)

Insignia SVG: ![badge](https://img.shields.io/badge/markdown-ok-brightgreen)

<p align="center"><img src="img/cafe.png" width="200" alt="html img"></p>

> [!NOTE]
> Un aviso de GitHub con **formato**.

> [!WARNING]
> Cuidado con esto.

<details><summary>Más detalles</summary>

Contenido plegable con <kbd>⌘</kbd> + <kbd>Space</kbd>.

</details>

## Casos hostiles (no deben cargar ni ejecutar)

![no es imagen](not-image.png)
![passwd](/etc/passwd)
![local red](http://127.0.0.1:8080/x.png)
![intranet](http://192.168.1.1/x.png)
<script>alert(1)</script> <iframe src="https://evil.example"></iframe> <img src=x onerror=alert(1)>
<a href="javascript:alert(1)" onclick="x()">enlace malo</a>
