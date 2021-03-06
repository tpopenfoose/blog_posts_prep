library(biomaRt)
ensembl = useMart("ensembl")
datasets <- listDatasets(ensembl)
datasets$orgDb <- NA

datasets[grep("hsapiens", datasets$dataset), "orgDb"] <- "org.Hs.eg.db"
datasets[grep("dmel", datasets$dataset), "orgDb"] <- "org.Dm.eg.db"
datasets[grep("mmus", datasets$dataset), "orgDb"] <- "org.Mm.eg.db"
datasets[grep("celegans", datasets$dataset), "orgDb"] <- "org.Ce.eg.db"
datasets[grep("cfam", datasets$dataset), "orgDb"] <- "org.Cf.eg.db"
datasets[grep("drerio", datasets$dataset), "orgDb"] <- "org.Dr.eg.db"
datasets[grep("ggallus", datasets$dataset), "orgDb"] <- "org.Gg.eg.db"
datasets[grep("ptrog", datasets$dataset), "orgDb"] <- "org.Pt.eg.db"
datasets[grep("rnor", datasets$dataset), "orgDb"] <- "org.Rn.eg.db"
datasets[grep("scer", datasets$dataset), "orgDb"] <- "org.Sc.sgd.db"
datasets[grep("sscrofa", datasets$dataset), "orgDb"] <- "org.Ss.eg.db"
#datasets[grep("xtrop", datasets$dataset), "orgDb"] <- "org.Xl.eg.db"

datasets <- datasets[!is.na(datasets$orgDb), ]

for (i in 1:nrow(datasets)) {
  ensembl <- datasets[i, 1]
  assign(paste0(ensembl), useMart("ensembl", dataset = paste0(ensembl)))
}

specieslist <- datasets$dataset


library(AnnotationDbi)

load_orgDb <- function(orgDb){

  if(!orgDb %in% installed.packages()[,"Package"]){
    source("https://bioconductor.org/biocLite.R")
    biocLite(orgDb)
  }
}

sapply(datasets$orgDb, load_orgDb, simplify = TRUE, USE.NAMES = TRUE)

lapply(datasets$orgDb, require, character.only = TRUE)

keytypes_list <- lapply(datasets$orgDb, function(x) NULL)
names(keytypes_list) <- paste(datasets$orgDb)

for (orgDb in datasets$orgDb){
  keytypes_list[[orgDb]] <- keytypes(get(orgDb))
}

library(rlist)
list.common(keytypes_list)


for (i in 1:nrow(datasets)){
  orgDbs <- datasets$orgDb[i]
  values <- keys(get(orgDbs), keytype = "ENTREZID")

  ds <- datasets$dataset[i]
  mart <- useMart("ensembl", dataset = paste(ds))
  print(mart)

  if (!is.na(listFilters(mart)$name[grep("^entrezgene$", listFilters(mart)$name)])){
    if (!is.na(listAttributes(mart)$name[grep("^entrezgene$", listAttributes(mart)$name)])){
    print("TRUE")
    for (species in specieslist) {
      print(species)
      if (species != ds){
        assign(paste("homologs", orgDbs, species, sep = "_"), getLDS(attributes = c("entrezgene"),
                                                                     filters = "entrezgene",
                                                                     values = values,
                                                                     mart = mart,
                                                                     attributesL = c("entrezgene"),
                                                                     martL = get(species)))
      }
    }
  }
  }
}





library(dplyr)

for (i in 1:nrow(datasets)){
  orgDbs <- datasets$orgDb[i]
  values <- data.frame(GeneID = keys(get(orgDbs), keytype = "ENTREZID"))
  values$GeneID <- as.character(values$GeneID)
  ds <- datasets$dataset[i]

  for (j in 1:length(specieslist)){
    species <- specieslist[j]

    if (j == 1){
      homologs_table <- values
    }

    if (species != ds){
      homologs_species <- get(paste("homologs", orgDbs, species, sep = "_"))
      homologs_species$EntrezGene.ID <- as.character(homologs_species$EntrezGene.ID)

      homologs <- left_join(values, homologs_species, by = c("GeneID" = "EntrezGene.ID"))
      homologs <- homologs[!duplicated(homologs$GeneID), ]
      colnames(homologs)[2] <- paste(species)

      homologs_table <- left_join(homologs_table, homologs, by = "GeneID")
  }
  }

  colnames(homologs_table)[1] <- paste(ds)

  assign(paste("homologs_table", ds, sep = "_"), homologs_table)
}


for (i in 1:nrow(datasets)){
  ds <- datasets$dataset[i]

  if (i == 1){
    homologs_table_combined <- get(paste("homologs_table", ds, sep = "_"))
    homologs_table_combined <- homologs_table_combined[, order(colnames(homologs_table_combined))]
  } else {
    homologs_table_species <- get(paste("homologs_table", ds, sep = "_"))
    homologs_table_species <- homologs_table_species[, order(colnames(homologs_table_species))]

    homologs_table_combined <- rbind(homologs_table_combined, homologs_table_species)
  }
}

homologs_table_combined <- homologs_table_combined[!duplicated(homologs_table_combined), ]

head(homologs_table_combined)
nrow(homologs_table_combined)

write.table(homologs_table_combined, "annotationdbi/homologs_table_combined_full_network.txt", row.names = F, col.names = T, sep = "\t")

homologs_table_combined_matrix <- as.matrix(ifelse(is.na(homologs_table_combined), 0, 1))

co_occurrence <- t(as.matrix(homologs_table_combined_matrix)) %*% as.matrix(homologs_table_combined_matrix)

library(igraph)
g <- graph_from_adjacency_matrix(co_occurrence,
                                 weighted = TRUE,
                                 diag = FALSE,
                                 mode = "undirected")

g <- simplify(g, remove.multiple = F, remove.loops = T, edge.attr.comb = c(weight = "sum", type = "ignore"))

datasets[, 2] <- gsub("(.*)( genes (.*))", "\\1", datasets[, 2])
datasets$description[grep("Saccharomyces", datasets$description)] <- "Yeast"
datasets$description[grep("elegans", datasets$description)] <- "C. elegans"

datasets$group <- ifelse(datasets$description == "Yeast", "fungus",
                         ifelse(datasets$description == "C. elegans", "roundworm",
                                ifelse(datasets$description == "Chicken", "bird",
                                       ifelse(datasets$dataset == "Zebrafish", "fish",
                                              ifelse(datasets$description == "Fruitfly", "insect", "mammal")))))

datasets$col <- ifelse(datasets$description == "Yeast", "deeppink3",
                         ifelse(datasets$description == "C. elegans", "deepskyblue1",
                                ifelse(datasets$description == "Chicken", "darkslateblue",
                                       ifelse(datasets$dataset == "Zebrafish", "darkorange3",
                                              ifelse(datasets$description == "Fruitfly", "darkred", "aquamarine4")))))

datasets <- left_join(datasets, data.frame(dataset = rownames(co_occurrence), no_genes = rowSums(co_occurrence)), by = "dataset")

V(g)$color <- datasets$col
V(g)$label <- datasets$description
V(g)$size <- datasets$no_genes/1000
E(g)$arrow.size <- 0.2
E(g)$edge.color <- "gray80"
E(g)$width <- E(g)$weight/100000

plot(g,
     vertex.label.font = 1,
     vertex.shape = "sphere",
     vertex.label.cex = 1,
     vertex.label.color = "black",
     vertex.frame.color = NA)
