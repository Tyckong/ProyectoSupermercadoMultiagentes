import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

df_optimized = pd.read_csv('resultados_validacion_OPTIMIZED_final.csv')
df_random = pd.read_csv('resultados_validacion_RANDOM_final.csv')

#Combine the dataframes into one for easier plotting and drop any rows that might be empty.
df_optimized = df_optimized[df_optimized['Modo'] != 'Mean Score']
df_random = df_random[df_random['Modo'] != 'Mean Score']

df_optimized = df_optimized.dropna(subset=['Modo'])
df_random = df_random.dropna(subset=['Modo'])

df_combined = pd.concat([df_optimized, df_random], ignore_index=True)

metrics = [
    'Ticks_Duracion',
    'Tiempo_Promedio_Compra',
    'Ingresos_Totales',
    'Ventas_Impulsivas',
    'Largo_Promedio_Cola'
]

sns.set(style="whitegrid")

#Boxplots.
plt.figure(figsize=(18, 12))
plt.suptitle('Comparison of Metrics: Optimized vs Random', fontsize=16)

for i, metric in enumerate(metrics):
    plt.subplot(2, 3, i + 1)  #Create a grid of 2 rows x 3 columns.
    sns.boxplot(x='Modo', y=metric, data=df_combined, palette="Set2")

    plt.title(metric.replace('_', ' '))
    plt.ylabel('Value')
    plt.xlabel('Mode')

plt.tight_layout(rect=[0, 0.03, 1, 0.95])  #Adjust layout to make room for subtitle.
plt.savefig('comparison_boxplots.png')
plt.show()

#Line Plots.
plt.figure(figsize=(18, 12))
plt.suptitle('Trends over Episodes', fontsize=16)

df_combined_sorted = df_combined.sort_values(by=['Modo', 'Episodio'])   #Sort by Episode to ensure lines are drawn correctly.

for i, metric in enumerate(metrics):
    plt.subplot(2, 3, i + 1)
    sns.lineplot(
        x='Episodio',
        y=metric,
        hue='Modo',
        data=df_combined_sorted,
        marker='o',
        palette="Set2"
    )

    plt.title(f'{metric.replace("_", " ")} over Episodes')
    plt.ylabel('Value')
    plt.xlabel('Episode')

plt.tight_layout(rect=[0, 0.03, 1, 0.95])
plt.savefig('trends_lineplots.png')
plt.show()