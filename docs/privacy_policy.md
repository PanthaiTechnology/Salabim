# Política de Privacidade — Salabim

**Última atualização:** 12 de agosto de 2026

O Salabim ("nós", "nosso app") é um aplicativo de reconhecimento musical que
ajuda você a identificar músicas por áudio (ouvindo a música tocando ou
cantarolando/assobiando a melodia) ou por texto (trecho de letra, descrição
livre). Esta política explica quais dados o app usa, com quem eles são
compartilhados, e por quanto tempo ficam guardados.

## 1. Dados que coletamos

### 1.1 Áudio do microfone
Quando você usa os modos **Ouvir** ou **Cantar**, o app grava um trecho curto
de áudio (poucos segundos) exclusivamente para identificar a música. Esse
áudio:

- É enviado, de forma criptografada, a um provedor de reconhecimento
  (**AudD**, para músicas tocando; **ACRCloud**, para melodia
  cantarolada/assobiada) — só o suficiente para eles devolverem o resultado
  do reconhecimento;
- Pode ser transcrito localmente, nos nossos próprios servidores (tecnologia
  Whisper, rodando em nossa infraestrutura, **não enviado a nenhum terceiro
  para essa etapa**), como um sinal auxiliar para confirmar o resultado do
  modo Cantar;
- **Não é armazenado de forma permanente.** Nós guardamos apenas um hash
  (uma impressão digital irreversível do áudio, não o áudio em si) associado
  ao resultado da busca, por até 24 horas, só para acelerar buscas repetidas
  do mesmo trecho — depois disso, some.

### 1.2 Texto de busca
Quando você usa a busca por texto (trecho de letra, nome de artista/música,
ou descrição livre), a consulta é enviada aos nossos servidores para buscar
correspondências no catálogo público de música (iTunes Search). Não
associamos essas buscas a uma identidade pessoal.

### 1.3 Histórico de buscas
O histórico das músicas que você já identificou fica guardado **somente no
seu aparelho** (armazenamento local do app) — nunca é enviado aos nossos
servidores nem a terceiros. Você pode apagar itens do histórico, ou apagar
tudo, a qualquer momento dentro do próprio app.

### 1.4 Correções que você envia
Se você usar a função de corrigir um resultado errado do modo Cantar (nome
real da música), essa correção é enviada aos nossos servidores para
melhorar buscas futuras de trechos parecidos. Não fica vinculada à sua
identidade — não temos sistema de conta/login.

## 2. Com quem compartilhamos dados

| Provedor | O que recebe | Para quê |
|---|---|---|
| AudD | trecho de áudio (modo Ouvir) | identificar a música tocando |
| ACRCloud | trecho de áudio (modo Cantar) | identificar a melodia cantarolada |
| Odesli/song.link | metadados da música (título, artista, ISRC) — nunca áudio | encontrar links da mesma música em outras plataformas de streaming |
| Spotify (API oficial) | título e artista — nunca áudio | confirmar o link oficial da faixa no Spotify quando necessário |
| iTunes Search (Apple) | texto da busca ou título/artista — nunca áudio | buscar catálogo de músicas, capas e prévias oficiais |

Não vendemos dados a ninguém. Não usamos os dados para publicidade.

## 3. Permissão de microfone

O Salabim pede acesso ao microfone **apenas para gravar o trecho de áudio
necessário pra identificar a música** nos modos Ouvir e Cantar. O app não
grava em segundo plano, não grava áudio contínuo, e não usa o microfone
para nenhum outro propósito.

## 4. Retenção e exclusão de dados

- Áudio bruto: nunca armazenado — processado e descartado na hora.
- Resultado de identificação (cache): até 24 horas, depois expira sozinho.
- Histórico local: fica no seu aparelho até você apagar (pelo app) ou
  desinstalar o aplicativo.
- Correções enviadas: guardadas indefinidamente para melhorar o
  reconhecimento, mas sem nenhum dado que identifique você pessoalmente.

## 5. Dados de crianças

O Salabim não é direcionado a crianças menores de 13 anos e não coleta
intencionalmente dados de menores.

## 6. Alterações nesta política

Podemos atualizar esta política conforme o app evolui. A data no topo
sempre reflete a versão mais recente.

## 7. Contato

Dúvidas sobre privacidade: ricardohmsoares@gmail.com
