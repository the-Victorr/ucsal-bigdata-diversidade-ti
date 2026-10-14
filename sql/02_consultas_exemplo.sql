-- Consultas de exemplo sobre a base carregada.
-- Reproduzem os números que aparecem no documento da etapa 2.
-- Rodar conectado ao banco do projeto.

-- 1. Quanto foi carregado
SELECT 'vinculos (RAIS 2025)'    AS medida, sum(qtd_vinculos)::bigint AS valor FROM dw.fato_vinculo_ti
UNION ALL
SELECT 'admissoes (CAGED 2025)',   sum(admissoes)    FROM dw.fato_movimentacao_ti
UNION ALL
SELECT 'desligamentos (CAGED 2025)', sum(desligamentos) FROM dw.fato_movimentacao_ti
UNION ALL
SELECT 'saldo do ano',              sum(saldo)        FROM dw.fato_movimentacao_ti;


-- 2. Tamanho ocupado no banco, por tabela
SELECT relname AS tabela,
       n_live_tup AS linhas,
       pg_size_pretty(pg_total_relation_size(relid)) AS tamanho
  FROM pg_stat_user_tables
 WHERE schemaname = 'dw'
 ORDER BY pg_total_relation_size(relid) DESC;


-- 3. O funil: participação de cada raça dentro de cada nível de cargo
SELECT n.nivel_lideranca_nome AS nivel,
       r.raca_cor_nome        AS raca_cor,
       sum(f.qtd_vinculos)    AS vinculos,
       round(100.0 * sum(f.qtd_vinculos)
             / sum(sum(f.qtd_vinculos)) OVER (PARTITION BY n.nivel_lideranca_nome), 1) AS pct_no_nivel
  FROM dw.fato_vinculo_ti f
  JOIN dw.dim_nivel_lideranca n USING (nivel_lideranca_id)
  JOIN dw.dim_raca_cor        r USING (raca_cor_id)
 WHERE n.degrau_funil <> 99          -- exclui o "nao classificado"
 GROUP BY 1, 2
 ORDER BY 1, 3 DESC;


-- 4. Gap salarial por sexo e raça.
--    A média é recalculada a partir das somas, porque média de média nao fecha.
SELECT s.sexo_nome,
       r.raca_cor_nome,
       sum(f.qtd_vinculos) AS vinculos,
       round(sum(f.soma_remuneracao) / nullif(sum(f.qtd_com_remuneracao), 0), 2) AS media_salarial
  FROM dw.fato_vinculo_ti f
  JOIN dw.dim_sexo     s USING (sexo_id)
  JOIN dw.dim_raca_cor r USING (raca_cor_id)
 WHERE r.declarada
 GROUP BY 1, 2
 ORDER BY media_salarial DESC;


-- 5. O mesmo gap, mas só entre quem tem superior completo.
--    Controla por qualificação: se a diferença persiste aqui, escolaridade nao explica.
SELECT s.sexo_nome,
       r.raca_cor_nome,
       sum(f.qtd_vinculos) AS vinculos,
       round(sum(f.soma_remuneracao) / nullif(sum(f.qtd_com_remuneracao), 0), 2) AS media_salarial
  FROM dw.fato_vinculo_ti f
  JOIN dw.dim_sexo         s USING (sexo_id)
  JOIN dw.dim_raca_cor     r USING (raca_cor_id)
  JOIN dw.dim_escolaridade e USING (escolaridade_id)
 WHERE r.declarada AND e.superior_completo
 GROUP BY 1, 2
 ORDER BY media_salarial DESC;


-- 6. Rotatividade mensal do setor em 2025
SELECT t.ano_mes,
       sum(f.admissoes)     AS admissoes,
       sum(f.desligamentos) AS desligamentos,
       sum(f.saldo)         AS saldo
  FROM dw.fato_movimentacao_ti f
  JOIN dw.dim_tempo t USING (tempo_id)
 GROUP BY 1
 ORDER BY 1;


-- 7. Participação feminina na chefia, por estado
SELECT u.uf_sigla,
       sum(f.qtd_vinculos) FILTER (WHERE s.sexo_codigo = 2) AS mulheres,
       sum(f.qtd_vinculos)                                  AS total,
       round(100.0 * sum(f.qtd_vinculos) FILTER (WHERE s.sexo_codigo = 2)
             / nullif(sum(f.qtd_vinculos), 0), 1)           AS pct_mulheres
  FROM dw.fato_vinculo_ti f
  JOIN dw.dim_uf              u USING (uf_id)
  JOIN dw.dim_sexo            s USING (sexo_id)
  JOIN dw.dim_nivel_lideranca n USING (nivel_lideranca_id)
 WHERE n.nivel_lideranca_codigo = 1
 GROUP BY 1
HAVING sum(f.qtd_vinculos) >= 100
 ORDER BY pct_mulheres DESC;


-- 8. Efeito da supressão de privacidade: quanto some entre o fato e a view publica
SELECT (SELECT count(*) FROM dw.fato_vinculo_ti)      AS linhas_no_fato,
       (SELECT count(*) FROM publico.vw_vinculo_ti)   AS linhas_publicadas;
