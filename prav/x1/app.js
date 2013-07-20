Ext.application({
    name: 'HelloExt',
    launch: function() {
        Ext.create('Ext.container.Viewport', {
            layout: 'fit',
            items: [
                {
                    title: 'Приложение на Ext JS 4',
                    html : '<h3>Добро пожаловать в мир Ext JS 4!</h3>'
                }
            ]
        });
    }
});