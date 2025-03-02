use_frameworks!

osx_deployment_target = '12.0'

$firebase_version = '10.29.0'

target 'Youchip-Stat' do
  platform :osx, osx_deployment_target
  pod 'TinyConstraints', '4.0.2'
  pod 'Moya/Combine', '15.0.0'
  pod 'SwiftyStoreKit', '0.16.1'
  pod 'SDWebImage', '5.19.6'
  pod 'Firebase/Analytics', $firebase_version
  pod 'Firebase/Crashlytics', $firebase_version
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    if target.respond_to?(:product_type) and target.product_type == "com.apple.product-type.bundle"
      target.build_configurations.each do |config|
        config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      end
    end
  end
  
  installer.generated_projects.each do |project|
    project.targets.each do |target|
      target.build_configurations.each do |config|
        if config.build_settings['MACOSX_DEPLOYMENT_TARGET'].to_f < osx_deployment_target.to_f
          config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = osx_deployment_target
        end
      end
    end
  end
end
