import React, { useEffect, useState } from 'react';
import { PhotoEditorSDKUI } from 'photoeditorsdk';

export const PhotoEditor = () => {
  const [editor, setEditor] = useState(null);
  const [exportedImageURL, setExportedImageURL] = useState('');

  const initEditor = async (imageBase64, isDraw) => {
    try {
      const tools =  [
          ['brush'],
          ['transform', 'filter', 'adjustment'],
          ['focus', 'frame'],
          ['text', 'textdesign', 'sticker'],
        ];

      const editorInstance = await PhotoEditorSDKUI.init({
        container: '#editor',
        license: '{"api_token":"uaEQUr3GJk6FpZHSaXmlhS1VK66pSIggNiASsLMKGkNr400s0mTv8ay8Hu_fMk4_","app_identifiers":[],"available_actions":[],"domains":["https://api.photoeditorsdk.com"],"enterprise_license":false,"expires_at":1789812000,"features":["camera","library","export","customassets","whitelabel","adjustment","brush","filter","focus","frame","overlay","sticker","text","textdesign","transform"],"issued_at":1726747492,"minimum_sdk_version":"1.0","owner":"SMM Service","platform":"HTML5","products":["pesdk"],"version":"2.4","signature":"gSulxF/J1Z4ILO02Fa8CONA8SJAE7p+QxepQ/rVM7wFC6+/lqJ4rCN87DUKEnotBbaEEhjY76To17PZQGeegGL9KARhSCiYiAQz46BgX1wdNKvZ9joFxm0mhYTXgBOs1mZcFOMFck5Kl+hgT0eaVMCFoMsTkRdFa53A/2BfJSvvEvKhYQ8TxQD8NXTG191O5F8PIxI4d2vNwK/vTdGx3ZEtKAGVZYzQX2Bb3sR4ehEmhvCzgJ21RL75ydaTAbEI5qHRKHSXsohy+4UQUb2w7LtBo5w4hvgCZAsQ5wr+3Nj2akreRvQxJhxrQTXSZARNr6tB0exb4J5NmctKPCK0UGiFR11PCLBfJ3gO8jzTDKPgCMJlCFQxK4PoZmI0wkYLKr4DODQi2blfe7uTA82k79fEtE8gT1KP4dA8TTt98AItpq1ZAYvAKLxPgSyrmKZZQ0GWG357bENOl1MwsM3kSLKr6kip92kMqDI3fA/eJqQYZx+qtzniobYrBsy0nicULnkKH7szJJ3s25FsQOb473WXXQDEWdrMFUfniVyL0owhG777q2tSJFzNYw5GhtlSGpKBODguLEAELXlTwxXweihEYTbWZgHcFtgpfWEicTVte7QYPP6l/c76NGEgLJGXEeJs4qIhaCQRfeu0AYzEB2nw1U/D7B+OEIH/sI5CwKCM="}',
        image: imageBase64,
        language: 'en',
        assetBaseUrl:
          'https://cdn.img.ly/packages/imgly/photoeditorsdk/5.19.0/assets',
        layout: 'basic',
        mainCanvasActions: ['undo', 'redo'],
        tools,
        brush: {
          colors: [
            { color: [1.00, 1.00, 1.00, 1], name: "white" },
            { color: [0.49, 0.49, 0.49, 1], name: "gray" },
            { color: [0.00, 0.00, 0.00, 1], name: "black" },
            { color: [0.40, 0.80, 1.00, 1], name: "light blue" },
            { color: [0.40, 0.53, 1.00, 1], name: "blue" },
            { color: [0.53, 0.40, 1.00, 1], name: "purple" },
            { color: [0.87, 0.40, 1.00, 1], name: "orchid" },
            { color: [1.00, 0.40, 0.80, 1], name: "pink" },
            { color: [0.90, 0.31, 0.31, 1], name: "red" },
            { color: [0.95, 0.53, 0.33, 1], name: "orange" },
            { color: [1.00, 0.80, 0.40, 1], name: "gold" },
            { color: [1.00, 0.97, 0.39, 1], name: "yellow" },
            { color: [0.80, 1.00, 0.40, 1], name: "olive" },
            { color: [0.33, 1.00, 0.53, 1], name: "green" },
            { color: [0.33, 1.00, 0.92, 1], name: "aquamarine" },
            { color: [0.75, 0.22, 0.17, 1], name: "crimson" },
            { color: [0.99, 0.50, 0.44, 1], name: "coral" },
            { color: [0.98, 0.92, 0.84, 1], name: "beige" },
            { color: [0.62, 0.32, 0.17, 1], name: "brown" },
            { color: [0.74, 0.72, 0.42, 1], name: "khaki" },
            { color: [0.54, 0.17, 0.89, 1], name: "violet" },
            { color: [0.72, 0.45, 0.20, 1], name: "sienna" },
            { color: [0.36, 0.20, 0.09, 1], name: "chocolate" },
            { color: [0.50, 0.50, 0.00, 1], name: "olive drab" },
            { color: [0.33, 0.42, 0.18, 1], name: "dark olive green" },
            { color: [0.11, 0.56, 0.56, 1], name: "cadet blue" },
            { color: [0.18, 0.31, 0.31, 1], name: "teal" },
            { color: [0.65, 0.74, 0.86, 1], name: "slate gray" },
            { color: [0.53, 0.81, 0.92, 1], name: "sky blue" },
            { color: [0.72, 0.53, 0.04, 1], name: "bronze" }
          ]
        },
      });

      setEditor(editorInstance);

      window.exportImage = exportImage;
    } catch (error) {
      console.error('Error initializing PhotoEditorSDKUI:', error);
    }
  };

  const exportImage = () => {
    if (!editor) {
      sendImageToNativeApp('');
      return;
    }


    editor
      .export({
        format: 'image/jpeg',
        exportType: 'data-url',
        quality: 1.0,
        enableDownload: false,
        preventExportEvent: true,
      })
      .then(function (dataURL) {
        var base64String = dataURL.split(',')[1];
        setExportedImageURL(dataURL);
        sendImageToNativeApp(base64String);
      })
      .catch(function (err) {
        sendImageToNativeApp('');
      });
  };

  const sendImageToNativeApp = (base64String) => {
    try {
      window.webkit.messageHandlers.imageExport.postMessage(base64String);
    } catch (error) {
      console.error('Error sending image to native app:', error);
    }
  };

  useEffect(() => {
    const handleMessage = (event) => {
      if (event.data.type === 'initEditor') {
        initEditor(event.data.imageBase64, event.data.isDraw);
      }
      if (event.data.type === 'updateEditor') {
        if (editor) {
          const image = new Image();
          image.onload = function () {
            editor.setImage(image);
          };
          image.src = event.data.imageBase64;
        }
      }
    };

    window.addEventListener('message', handleMessage);

    return () => {
      window.removeEventListener('message', handleMessage);
    };
  }, [editor]);

  return (
    <div style={{ position: 'relative', width: '100vw', height: '100vh' }}>
      <div id="editor" style={{ width: '100%', height: '100%' }}></div>
      <button
        id="exportButton"
        onClick={exportImage}
        style={{
          position: 'absolute',
          top: '0px',
          right: '0px',
          zIndex: 1000,
          fontSize: '0px',
          backgroundColor: exportedImageURL ? 'red' : '#4CAF50',
          color: 'white',
          border: 'none',
          cursor: 'pointer',
          opacity: '0.0'
        }}
      >
        {exportedImageURL ? (
          <a
            href={exportedImageURL}
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: 'white', textDecoration: 'none' }}
          >
          </a>
        ) : (
          'Export Image'
        )}
      </button>
    </div>
  );
};