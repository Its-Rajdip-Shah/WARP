"""Build a local VSIX with only Python's standard library; no npm downloads."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import sys
root = Path(__file__).resolve().parent
output = Path(sys.argv[1]) if len(sys.argv)>1 else Path('/tmp/warp-companion-0.1.0.vsix')
with ZipFile(output, 'w', ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="application/json"/><Default Extension="js" ContentType="application/javascript"/><Default Extension="vsixmanifest" ContentType="text/xml"/></Types>')
    z.writestr('extension.vsixmanifest', '''<?xml version="1.0"?><PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"><Metadata><Identity Language="en-US" Id="warp-companion" Version="0.1.0" Publisher="warp-local"/><DisplayName>WARP Workspace Companion</DisplayName><Description xml:space="preserve">Verified local workspace descriptors for WARP.</Description><Tags>workspace</Tags><Categories>Other</Categories><GalleryFlags>Public</GalleryFlags><Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.85.0"/></Properties></Metadata><Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Dependencies/><Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets></PackageManifest>''')
    for name in ('package.json','extension.js'):
        z.write(root/name, 'extension/'+name)
print(output)
