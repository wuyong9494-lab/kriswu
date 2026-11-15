"""Private exact GLSL-to-Metal source-expression adapter for scoped D15 FX.

The original compiled program remains an external, digest-verified input. This
module changes vector/API interfaces; it does not replace source equations.
It has no import-time file or network operations.
"""
from pathlib import Path
import hashlib
import json
import re
from sun_triad_assets import require, write_private

def sha(b):
    return hashlib.sha256(b).hexdigest()

def typ(s):
    return re.sub('\\b(?:[biu]?vec[234]|mat[234])\\b', lambda m: {'vec': 'float', 'bvec': 'bool', 'ivec': 'int', 'uvec': 'uint', 'mat': 'float'}[m.group()[:-1]] + m.group()[-1] + ('x' + m.group()[-1] if m.group().startswith('mat') else ''), s)

def section(s, stage):
    s = s[s.index('#ifdef ' + stage + '\n'):]
    if stage == 'VERTEX':
        s = s[:s.index('#ifdef FRAGMENT')]
    body = s.split('void main()', 1)[1]
    a = body.index('{')
    b = body.rfind('}')
    body = body[a + 1:b]
    header = s[:s.index('void main()')]
    uniforms = []
    for line in header.splitlines():
        q = re.search('\\buniform\\s+(?:(?:highp|mediump|lowp)\\s+)?(\\w+)\\s+(\\w+)(\\[4\\])?;', line)
        if q:
            uniforms.append((q[1], q[2], bool(q[3])))
    ins = re.findall('^in\\s+(?:(?:highp|mediump|lowp)\\s+)?\\s*(\\w+)\\s+(\\w+)\\s*;', header, re.M)
    outs = re.findall('^out\\s+(?:(?:highp|mediump|lowp)\\s+)?\\s*(\\w+)\\s+(\\w+)\\s*;', header, re.M)
    temps = []
    for line in header.splitlines():
        q = re.fullmatch('(?:(?:highp|mediump|lowp)\\s+)?((?:float|int|bool|[biu]?vec[234])\\s+\\w+);', line)
        if q:
            temps.append(typ(q[1]) + ';')
    return dict(body=body, uniforms=uniforms, inputs=ins, outputs=outs, temps=temps)
BUILTIN = {'_Time', '_WorldSpaceCameraPos', 'hlslcc_mtx4x4unity_ObjectToWorld', 'hlslcc_mtx4x4unity_WorldToObject', 'hlslcc_mtx4x4unity_MatrixV', 'hlslcc_mtx4x4unity_MatrixVP', 'hlslcc_mtx4x4glstate_matrix_projection'}
HEADER = '#include <metal_stdlib>\nusing namespace metal;\nstruct TriadVertex { float4 position, normal, tangent, color, uv0, uv1; };\nstruct TriadUniforms { float4 data[96]; };\ninline float triad_component(int s, float2 uv0, float2 uv1, constant TriadUniforms& u) {\n    if (s == 0) return 0.0f; if (s == 1) return 1.0f;\n    if (s < 4) return uv0[s-2]; if (s < 6) return uv1[s-4];\n    if (s < 10) return u.data[23][s-6];\n    if (s < 14) return u.data[24][s-10];\n    return u.data[25][s-14];\n}\ninline float4 triad_texcoord(int slot, float2 uv0, float2 uv1, constant TriadUniforms& u) {\n    float4 s=u.data[28+slot];\n    return float4(triad_component(int(s.x),uv0,uv1,u),triad_component(int(s.y),uv0,uv1,u),triad_component(int(s.z),uv0,uv1,u),triad_component(int(s.w),uv0,uv1,u));\n}\n'

def declarations(stage, unames):
    out = []
    mapping = {'_Time': 'u.data[21]', '_WorldSpaceCameraPos': 'u.data[20].xyz', 'hlslcc_mtx4x4unity_ObjectToWorld': 'float4x4(u.data[0],u.data[1],u.data[2],u.data[3])', 'hlslcc_mtx4x4unity_WorldToObject': 'float4x4(u.data[4],u.data[5],u.data[6],u.data[7])', 'hlslcc_mtx4x4unity_MatrixV': 'float4x4(u.data[8],u.data[9],u.data[10],u.data[11])', 'hlslcc_mtx4x4glstate_matrix_projection': 'float4x4(u.data[12],u.data[13],u.data[14],u.data[15])', 'hlslcc_mtx4x4unity_MatrixVP': 'float4x4(u.data[16],u.data[17],u.data[18],u.data[19])'}
    for t, n, array in stage['uniforms']:
        if t == 'sampler2D':
            continue
        expr = mapping.get(n)
        if expr is None:
            expr = f'u.data[{32 + unames.index(n)}]' + ('.x' if t == 'float' else '.xyz' if t == 'vec3' else '')
            if t == 'int':
                # The source Fresnel variant stores _Invert as an integer.
                # The shared uniform buffer stores material scalars as floats;
                # preserve the explicit GLSL integer read at this interface.
                expr = f'int(u.data[{32 + unames.index(n)}].x)'
        out.append(f"    {('float4x4' if array else typ(t))} {n} = {expr};")
    return '\n'.join(out)

def convert_body(body, fields, prefix, fragment=False):
    body = typ(body)
    body = re.sub('\\binversesqrt\\b', 'rsqrt', body)
    for name in fields:
        body = re.sub('\\b' + re.escape(name) + '\\b', prefix + '.' + name, body)
    if fragment:
        body = re.sub('texture\\((\\w+), ([^)]+)\\)', lambda q: f'{q[1]}.sample({q[1]}Sampler, {q[2]})', body)
        body = body.replace('return;', 'return SV_Target0;')
    else:
        body = body.replace('gl_Position', 'o.position').replace('return;', 'return o;')
    require(not re.search('\\b(texture|vec[234]|mat[234]|inversesqrt)\\s*\\(', body), 'Unadapted original GLSL interface or render state')
    return body

def translate(bindings, output):
    programs = {}
    patches = []
    for m in bindings['materials']:
        if not m['exactMatches']:
            continue
        require(len(m['exactMatches']) == 1, 'Unadapted original GLSL interface or render state')
        match = m['exactMatches'][0]
        key = match['glslSHA256']
        sid = m['shaderPathID']
        shader = next((s for s in bindings['shaders'] if s['pathID'] == sid))
        parsed = json.loads(Path(shader['parsedFile']).read_text())
        if key not in programs:
            source = Path(match['glslFile']).read_bytes()
            require(sha(source) == key, 'Unadapted original GLSL interface or render state')
            v = section(source.decode(), 'VERTEX')
            f = section(source.decode(), 'FRAGMENT')
            uni = {n: t for s in (v, f) for t, n, a in s['uniforms'] if n not in BUILTIN and t != 'sampler2D'}
            names = sorted(uni)
            require(len(names) <= 64, 'Unadapted original GLSL interface or render state')
            texture_names = sorted({n for s in (v, f) for t, n, a in s['uniforms'] if t == 'sampler2D'})
            require(len(texture_names) <= 8, 'Unadapted original GLSL interface or render state')
            prefix = 'd15_' + key[:20]
            vf = prefix + '_v'
            ff = prefix + '_f'
            shared = {n: t for t, n in v['outputs']}
            require(all((shared.get(n) == t for t, n in f['inputs'])), 'Unadapted original GLSL interface or render state')
            io = 'struct TriadIO { float4 position [[position]];\n' + ''.join((f'    {typ(t)} {n};\n' for n, t in shared.items())) + '};\n'
            code = HEADER + io + f'vertex TriadIO {vf}(uint id [[vertex_id]], const device TriadVertex* vertices [[buffer(0)]], constant TriadUniforms& u [[buffer(2)]]) {{\n    TriadIO o; TriadVertex a=vertices[id];\n'
            code += '    float2 uv0=float2(a.uv0.x,1.0f-a.uv0.y)*u.data[26].zw+u.data[26].xy;\n    float2 uv1=float2(a.uv1.x,1.0f-a.uv1.y);\n'
            for t, n in v['inputs']:
                if n == 'in_POSITION0':
                    expr = 'float4(a.position.xyz*float3(1.0f,1.0f,-1.0f)/u.data[27].x,1.0f)'
                elif n == 'in_NORMAL0':
                    expr = 'u.data[27].y>0.5f ? a.normal.xyz*float3(1.0f,1.0f,-1.0f) : float3(0.0f)'
                elif n == 'in_TANGENT0':
                    expr = 'u.data[27].z>0.5f ? a.tangent*float4(1.0f,1.0f,-1.0f,-1.0f) : float4(0.0f,0.0f,0.0f,1.0f)'
                elif n == 'in_COLOR0':
                    expr = 'u.data[27].w>0.5f ? a.color*u.data[22] : float4(0.0f,0.0f,0.0f,1.0f)'
                elif re.fullmatch('in_TEXCOORD[0-3]', n):
                    expr = f'triad_texcoord({n[-1]},uv0,uv1,u)' + ('.xy' if t == 'vec2' else '.xyz' if t == 'vec3' else '')
                else:
                    raise ValueError(n)
                code += f'    {typ(t)} {n} = {expr};\n'
            code += declarations(v, names) + '\n' + '\n'.join(('    ' + x for x in v['temps'])) + '\n' + convert_body(v['body'], shared, 'o') + '\n}\n'
            args = ', '.join((f'texture2d<float> {n} [[texture({i})]], sampler {n}Sampler [[sampler({i})]]' for i, n in enumerate(texture_names)))
            code += f'fragment float4 {ff}(TriadIO i [[stage_in]], constant TriadUniforms& u [[buffer(2)]]' + (', ' + args if args else '') + ') {\n    float4 SV_Target0;\n'
            code += declarations(f, names) + '\n' + '\n'.join(('    ' + x for x in f['temps'])) + '\n' + convert_body(f['body'], [n for t, n in f['inputs']], 'i', True) + '\n}\n'
            require('#version' not in code, 'Unadapted original GLSL interface or render state')
            filename = 'SF3D15FX_' + key[:20] + '.metal'
            raw = code.encode()
            write_private(output / filename, raw)
            props = {p['m_Name']: p for p in parsed['m_PropInfo']['m_Props']}
            uniforms = []
            for n in names:
                width = {'float': 1, 'int': 1, 'vec2': 2, 'vec3': 3, 'vec4': 4}[uni[n]]
                q = dict(name=n, width=width)
                if n in props:
                    q['defaultValue'] = [props[n][f'm_DefValue[{i}]'] for i in range(4)]
                uniforms.append(q)
            programs[key] = dict(file=filename, bytes=len(raw), sha256=sha(raw), vertexFunction=vf, fragmentFunction=ff, uniforms=uniforms, textures=texture_names, layoutVersion=1)
        mat = json.loads(Path(m['metadataFile']).read_text())
        saved = mat['m_SavedProperties']
        floats = dict(saved['m_Floats'])
        colors = dict(saved['m_Colors'])
        state = parsed['m_SubShaders'][match['subshader']]['m_Passes'][match['passIndex']]['m_State']
        props = {p['m_Name']: p for p in parsed['m_PropInfo']['m_Props']}

        def value(q):
            n = q['name']
            if n and n != '<noninit>':
                if n in floats:
                    return floats[n]
                if n in props:
                    return props[n]['m_DefValue[0]']
                raise ValueError(('missing render state', n))
            return q['val']
        require(value(state['alphaToMask']) == 0 and value(state['zClip']) == 1, 'Unadapted original GLSL interface or render state')
        require(value(state['offsetFactor']) == value(state['offsetUnits']) == 0, 'Unadapted original GLSL interface or render state')
        for side in ('stencilOp', 'stencilOpFront', 'stencilOpBack'):
            require(value(state[side]['comp']) == 8, 'Unadapted original GLSL interface or render state')
            require(all((value(state[side][k]) == 0 for k in ('fail', 'pass', 'zFail'))), 'Unadapted original GLSL interface or render state')
        blend = state['rtBlend0']
        require(value(blend['colMask']) in (14, 15), 'Unadapted original GLSL interface or render state')
        s, d = (int(value(blend['srcBlend'])), int(value(blend['destBlend'])))
        require(s == value(blend['srcBlendAlpha']) and d == value(blend['destBlendAlpha']), 'Unadapted original GLSL interface or render state')
        require(value(blend['blendOp']) == value(blend['blendOpAlpha']) == 0, 'Unadapted original GLSL interface or render state')
        require((s, d) in ((1, 10), (1, 1), (5, 10), (5, 1)), str((m['sourceName'], s, d)))
        raster = dict(source=s, destination=d, cull=int(value(state['culling'])), zWrite=bool(value(state['zWrite'])), zTest=int(value(state['zTest'])), colorMask=int(value(blend['colMask'])))
        patches.append(dict(sourceMaterialPathID=m['sourcePathID'], sourceMaterialSHA256=m['sourceObjectSHA256'], sourceShaderSHA256=shader['sourceObjectSHA256'], variantSHA256=key, sourceName=m['sourceName'], shaderPathID=sid, projectColorSpace=0, projectAnisotropicFiltering=0, program=programs[key], raster=raster))
    return dict(version=1, programDirectory=str(output), materials=patches)
