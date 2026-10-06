# DF Office — atualizações

Pacotes de atualização do sistema DF Office, usado internamente pela FG Consultoria.

O servidor do escritório consulta o arquivo `manifest.json` deste repositório para
saber se existe versão nova, baixa o pacote, confere a assinatura SHA256 e aplica
sozinho. Não é preciso copiar arquivos.

## Como o servidor atualiza

Na pasta da instalação, basta executar como administrador:

```
ATUALIZAR_ONLINE.cmd
```

Ele faz tudo: compara a versão, baixa, confere a integridade, para o serviço,
aplica, devolve o controle para a tarefa agendada e mostra a versão final. Se algo
falhar, restaura a versão anterior.

O endereço consultado fica em `config.json`, na chave `updateManifestUrl`.

## O que tem aqui

| Arquivo | Para que serve |
|---|---|
| `manifest.json` | Versão publicada, endereço do pacote e assinatura SHA256 |
| `pacotes/` | Os pacotes de atualização |

## O que NÃO tem aqui

Nenhum dado de cliente, de colaborador ou de acesso. O pacote de atualização
carrega apenas o programa. A base de dados, os cadastros e as credenciais ficam
só no servidor do escritório, no arquivo `data/db.json`, que nunca sai de lá.

## Publicar uma versão nova

1. Gerar o pacote no projeto do sistema.
2. Copiar o ZIP para `pacotes/`.
3. Atualizar o `manifest.json` com a versão, o endereço e o SHA256 novos.
4. Commit e push.

A partir daí, o servidor encontra a atualização sozinho.
