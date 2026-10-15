"""
Parecer gerado pelo Claude (API da Anthropic) a partir dos resultados de uma sessão.

O modelo recebe apenas números já calculados (classes por batimento, BPM, VFC, qualidade
do sinal) — nunca o sinal bruto — e escreve uma interpretação em linguagem clara.
"""
import json
import os
from collections import Counter

import anthropic

MODEL = os.getenv('CLAUDE_MODEL', 'claude-opus-5-5')

SYSTEM = """Você é um assistente de apoio à análise de eletrocardiogramas em um projeto acadêmico \
de engenharia biomédica. O sistema é um ECG de uma derivação montado com ESP32 + módulo AD8232, \
amostrado a 100 Hz, cujos batimentos são classificados por um Random Forest treinado no \
MIT-BIH Arrhythmia Database reamostrado para 100 Hz. Normalmente o modelo usa as classes do padrão \
AAMI: N (normal, inclui bloqueios de ramo, que este modelo não distingue), S (ectópico \
supraventricular), V (ectópico ventricular) e F (fusão). A legenda das classes vem junto dos dados.

Escreva um parecer técnico em português do Brasil, em Markdown, com as seções:
1. **Resumo** — 2 a 3 frases com o achado principal.
2. **Frequência e ritmo** — BPM, classificação (bradicardia < 60, normal 60–100, taquicardia > 100), \
regularidade dos intervalos RR e métricas de VFC.
3. **Classificação dos batimentos** — o que as classes encontradas significam e quão consistentes \
foram entre as medições.
4. **Qualidade e confiabilidade** — qualidade do sinal, medições com erro, confiança do modelo, e as \
limitações conhecidas (ECG de 1 derivação, 100 Hz; em pacientes novos o modelo é confiável para N e \
razoável para V, mas fraco para S e F; diferença entre o MIT-BIH e o hardware próprio).
5. **Sugestões** — o que repetir, verificar ou observar.

Seja objetivo e honesto sobre a incerteza: se os dados forem inconsistentes ou de baixa qualidade, \
diga isso em vez de forçar uma conclusão. Isto NÃO é um diagnóstico médico; termine com uma linha \
lembrando que achados relevantes devem ser avaliados por um cardiologista com ECG de 12 derivações."""


def resumo_sessao(sessao, classes):
    """Condensa a sessão em um JSON compacto para o prompt."""
    medicoes, todos_labels, confs = [], Counter(), []
    for m in sessao['medicoes']:
        labels = [b['pred_label'] for b in m['beats'] if b['pred_label']]
        todos_labels.update(labels)
        confs += [b['confidence'] for b in m['beats'] if b['confidence'] is not None]
        medicoes.append({
            'id': m['id'],
            'erro': m['error'],
            'bpm': m['bpm'],
            'classe_ultimo_batimento': m['classe'],
            'distribuicao_batimentos': m['distribuicao'],
            'vfc': m['hrv'],
            'n_picos_r': len(m['rpeaks'] or []),
        })
    bpms = [m['bpm'] for m in sessao['medicoes'] if m['bpm']]
    return {
        'sessao_id': sessao['id'],
        'inicio': sessao['started_at'],
        'paciente': sessao.get('patient'),
        'observacoes': sessao.get('notes'),
        'n_medicoes': len(medicoes),
        'n_medicoes_com_erro': sum(1 for m in medicoes if m['erro']),
        'bpm_medio': round(sum(bpms) / len(bpms), 1) if bpms else None,
        'classe_final_votacao': sessao.get('classe_final'),
        'total_batimentos_por_classe': dict(todos_labels),
        'confianca_media_modelo': round(sum(confs) / len(confs), 3) if confs else None,
        'legenda_classes': {k: classes.get(k, k) for k in todos_labels},
        'medicoes': medicoes,
    }


class ParecerError(Exception):
    pass


def gerar_parecer(sessao, classes):
    if not sessao['medicoes']:
        raise ParecerError('Sessão sem medições.')

    client = anthropic.Anthropic()  # usa ANTHROPIC_API_KEY (ou perfil do `ant auth login`)
    dados = json.dumps(resumo_sessao(sessao, classes), ensure_ascii=False, indent=1)

    try:
        response = client.beta.messages.create(
            model=MODEL,
            max_tokens=16000,
            thinking={'type': 'adaptive'},
            output_config={'effort': 'medium'},
            # Se o modelo recusar por política de segurança, a API refaz com um modelo substituto
            betas=['server-side-fallback-2026-07-01'],
            fallbacks='default',
            system=SYSTEM,
            messages=[{
                'role': 'user',
                'content': f'Dados da sessão de ECG:\n```json\n{dados}\n```\nEscreva o parecer.',
            }],
        )
    except anthropic.AuthenticationError:
        raise ParecerError('Chave da API da Anthropic inválida (confira ANTHROPIC_API_KEY no .env).')
    except TypeError as e:  # o SDK lança TypeError quando não há nenhuma credencial configurada
        if 'authentication' not in str(e):
            raise
        raise ParecerError('Chave da API da Anthropic ausente: defina ANTHROPIC_API_KEY no arquivo .env e reinicie o servidor.')
    except anthropic.RateLimitError:
        raise ParecerError('Limite de requisições da API atingido. Tente novamente em instantes.')
    except anthropic.APIStatusError as e:
        raise ParecerError(f'Erro da API ({e.status_code}): {e.message}')
    except anthropic.APIConnectionError:
        raise ParecerError('Sem conexão com a API da Anthropic.')

    if response.stop_reason == 'refusal':
        raise ParecerError('O modelo recusou gerar o parecer para estes dados.')

    texto = ''.join(b.text for b in response.content if b.type == 'text').strip()
    if not texto:
        raise ParecerError('A API retornou uma resposta vazia.')
    return texto, response.model
